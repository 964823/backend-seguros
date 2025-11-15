CREATE TYPE role AS ENUM ('lojista', 'profissional', 'admin');
CREATE TYPE area_atuacao AS ENUM ('eletrica', 'hidraulica', 'chaveiro');

CREATE TABLE profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    full_name TEXT,
    role role
);

CREATE TABLE lojistas (
    id UUID PRIMARY KEY REFERENCES profiles(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    cnpj TEXT UNIQUE,
    endereco_principal TEXT,
    mensalidade_ativa BOOLEAN DEFAULT false
);

CREATE TABLE profissionais (
    id UUID PRIMARY KEY REFERENCES profiles(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    area_atuacao area_atuacao,
    pix_key TEXT UNIQUE,
    is_validated BOOLEAN DEFAULT false
);

CREATE TYPE tipo_servico AS ENUM ('simples', 'extra');
CREATE TYPE status_chamado AS ENUM ('pendente', 'aceito', 'a_caminho', 'em_servico', 'finalizado_prof', 'aprovado_lojista', 'validado_adm');
CREATE TYPE status_pagamento AS ENUM ('pendente', 'pago');
CREATE TYPE tipo_cobranca AS ENUM ('mensalidade', 'servico_extra');
CREATE TYPE status_cobranca AS ENUM ('pendente', 'pago', 'falhou');

CREATE TABLE chamados (
    id SERIAL PRIMARY KEY,
    lojista_id UUID REFERENCES lojistas(id),
    profissional_id UUID REFERENCES profissionais(id),
    tipo_servico tipo_servico,
    descricao TEXT,
    valor_cobrado_extra NUMERIC,
    status status_chamado
);

CREATE TABLE transacoes (
    id SERIAL PRIMARY KEY,
    chamado_id INTEGER REFERENCES chamados(id),
    profissional_id UUID REFERENCES profissionais(id),
    valor_bruto NUMERIC,
    comissao_plataforma NUMERIC,
    valor_liquido_prof NUMERIC,
    status_pagamento status_pagamento
);

CREATE TABLE cobrancas (
    id SERIAL PRIMARY KEY,
    lojista_id UUID REFERENCES lojistas(id),
    tipo_cobranca tipo_cobranca,
    valor NUMERIC,
    data_vencimento DATE,
    status_cobranca status_cobranca
);

ALTER TABLE cobrancas ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Lojistas can view their own cobrancas."
ON cobrancas
FOR SELECT
USING (
  (SELECT role FROM profiles WHERE profiles.id = auth.uid()) = 'lojista' AND
  lojista_id = auth.uid()
);

CREATE POLICY "Admins have full access to cobrancas."
ON cobrancas
FOR ALL
USING (
  (SELECT role FROM profiles WHERE profiles.id = auth.uid()) = 'admin'
)
WITH CHECK (
  (SELECT role FROM profiles WHERE profiles.id = auth.uid()) = 'admin'
);

CREATE TABLE avaliacoes (
    id SERIAL PRIMARY KEY,
    chamado_id INTEGER UNIQUE REFERENCES chamados(id),
    lojista_id UUID REFERENCES lojistas(id),
    profissional_id UUID REFERENCES profissionais(id),
    nota INTEGER CHECK (nota >= 1 AND nota <= 5),
    comentario TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE avaliacoes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can see all reviews."
ON avaliacoes
FOR SELECT
USING (
  auth.role() = 'authenticated'
);

CREATE POLICY "Lojistas can create reviews for their own validated chamados."
ON avaliacoes
FOR INSERT
WITH CHECK (
  (SELECT role FROM profiles WHERE profiles.id = auth.uid()) = 'lojista' AND
  lojista_id = auth.uid() AND
  EXISTS (SELECT 1 FROM chamados WHERE chamados.id = chamado_id AND chamados.lojista_id = auth.uid() AND chamados.status = 'validado_adm')
);

CREATE POLICY "Lojistas can update/delete their own reviews."
ON avaliacoes
FOR UPDATE, DELETE
USING (
  (SELECT role FROM profiles WHERE profiles.id = auth.uid()) = 'lojista' AND
  lojista_id = auth.uid()
);

CREATE POLICY "Admins have full access to avaliacoes."
ON avaliacoes
FOR ALL
USING (
  (SELECT role FROM profiles WHERE profiles.id = auth.uid()) = 'admin'
)
WITH CHECK (
  (SELECT role FROM profiles WHERE profiles.id = auth.uid()) = 'admin'
);

CREATE TABLE notificacoes (
    id SERIAL PRIMARY KEY,
    user_id UUID REFERENCES profiles(id),
    type TEXT,
    title TEXT,
    content TEXT,
    is_read BOOLEAN DEFAULT false,
    related_id INTEGER,
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE notificacoes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage their own notifications."
ON notificacoes
FOR SELECT, UPDATE, DELETE
USING (
  auth.uid() = user_id
);

CREATE POLICY "Admins have full access to notifications."
ON notificacoes
FOR ALL
USING (
  (SELECT role FROM profiles WHERE profiles.id = auth.uid()) = 'admin'
)
WITH CHECK (
  (SELECT role FROM profiles WHERE profiles.id = auth.uid()) = 'admin'
);
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own profile."
ON profiles
FOR SELECT
USING (
  auth.uid() = id
);
ALTER TABLE lojistas ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Lojistas can view their own data."
ON lojistas
FOR SELECT
USING (
  auth.uid() = id AND
  (SELECT role FROM profiles WHERE profiles.id = auth.uid()) = 'lojista'
);

CREATE POLICY "Admins have full access to lojistas."
ON lojistas
FOR ALL
USING (
  (SELECT role FROM profiles WHERE profiles.id = auth.uid()) = 'admin'
)
WITH CHECK (
  (SELECT role FROM profiles WHERE profiles.id = auth.uid()) = 'admin'
);

ALTER TABLE profissionais ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Profissionais can view their own data."
ON profissionais
FOR SELECT
USING (
  auth.uid() = id AND
  (SELECT role FROM profiles WHERE profiles.id = auth.uid()) = 'profissional'
);

CREATE POLICY "Admins have full access to profissionais."
ON profissionais
FOR ALL
USING (
  (SELECT role FROM profiles WHERE profiles.id = auth.uid()) = 'admin'
)
WITH CHECK (
  (SELECT role FROM profiles WHERE profiles.id = auth.uid()) = 'admin'
);

ALTER TABLE chamados ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can see relevant chamados based on their role."
ON chamados
FOR SELECT
USING (
  (
    (SELECT role FROM profiles WHERE profiles.id = auth.uid()) = 'lojista' AND
    lojista_id = auth.uid()
  ) OR (
    (SELECT role FROM profiles WHERE profiles.id = auth.uid()) = 'profissional' AND
    (profissional_id = auth.uid() OR status = 'pendente')
  )
);

CREATE OR REPLACE FUNCTION aceitar_chamado(p_chamado_id integer, p_profissional_id uuid)
RETURNS chamados
LANGUAGE plpgsql
AS $$
DECLARE
  updated_chamado chamados;
BEGIN
  UPDATE chamados
  SET
    profissional_id = p_profissional_id,
    status = 'aceito'
  WHERE
    id = p_chamado_id AND status = 'pendente'
  RETURNING * INTO updated_chamado;

  IF updated_chamado IS NULL THEN
    RAISE EXCEPTION 'Chamado não está pendente ou não foi encontrado.';
  END IF;

  RETURN updated_chamado;
END;
$$;

CREATE OR REPLACE FUNCTION iniciar_cobranca_mensalidade(p_lojista_id uuid, p_valor numeric, p_dias_vencimento integer)
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
  new_cobranca_id integer;
BEGIN
  INSERT INTO cobrancas (lojista_id, tipo_cobranca, valor, data_vencimento, status_cobranca)
  VALUES (p_lojista_id, 'mensalidade', p_valor, current_date + p_dias_vencimento, 'pendente')
  RETURNING id INTO new_cobranca_id;

  RETURN new_cobranca_id;
END;
$$;

CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO public.profiles (id, role)
  VALUES (NEW.id, 'lojista');
  RETURN NEW;
END;
$$;

CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION public.handle_new_user();