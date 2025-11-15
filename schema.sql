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

ALTER TABLE lojistas ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Lojistas can view their own data."
ON lojistas
FOR SELECT
USING (
  auth.uid() = id AND
  (SELECT role FROM profiles WHERE profiles.id = auth.uid()) = 'lojista'
);

ALTER TABLE profissionais ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Profissionais can view their own data."
ON profissionais
FOR SELECT
USING (
  auth.uid() = id AND
  (SELECT role FROM profiles WHERE profiles.id = auth.uid()) = 'profissional'
);