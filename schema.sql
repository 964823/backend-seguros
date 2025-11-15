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