CREATE TABLE IF NOT EXISTS public.company_mail_server (
    id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    company_id      bigint NOT NULL,
    smtp_host       varchar(150) NOT NULL,
    smtp_port       integer NOT NULL DEFAULT 587,
    smtp_secure     boolean NOT NULL DEFAULT false,
    smtp_user       varchar(150) NOT NULL,
    smtp_pass       varchar(255) NOT NULL,
    from_name       varchar(150) NOT NULL,
    from_email      varchar(150),
    reply_to        varchar(150),
    is_active       boolean NOT NULL DEFAULT true,
    is_deleted      boolean NOT NULL DEFAULT false,
    create_date     timestamp with time zone DEFAULT now(),
    write_date      timestamp with time zone DEFAULT now(),
    CONSTRAINT uq_company_mail_server_company UNIQUE (company_id)
);

INSERT INTO public.company_mail_server (
    company_id, smtp_host, smtp_port, smtp_secure, smtp_user, smtp_pass, from_name, from_email, reply_to, is_active, is_deleted
) VALUES (
    1, 'smtp.gmail.com', 465, true, 'linksoft151@gmail.com', 'redtfwmgdgocrjle', 'Hotel Aventura Perú', 'linksoft151@gmail.com', 'linksoft151@gmail.com', true, false
) ON CONFLICT (company_id) DO UPDATE SET
    smtp_host = EXCLUDED.smtp_host,
    smtp_port = EXCLUDED.smtp_port,
    smtp_secure = EXCLUDED.smtp_secure,
    smtp_user = EXCLUDED.smtp_user,
    smtp_pass = EXCLUDED.smtp_pass,
    from_name = EXCLUDED.from_name,
    from_email = EXCLUDED.from_email,
    reply_to = EXCLUDED.reply_to,
    is_active = true,
    is_deleted = false;
