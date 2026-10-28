import { BadRequestException, Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import fs from 'node:fs';
import path from 'node:path';
import nodemailer from 'nodemailer';
import { TenantDatabaseService } from '../tenant-database/tenant-database.service';

export interface CompanyMailServerConfig {
  id?: number;
  company_id: number;
  smtp_host: string;
  smtp_port: number;
  smtp_secure: boolean;
  smtp_user: string;
  smtp_pass?: string;
  from_name: string;
  from_email?: string;
  reply_to?: string;
  is_active?: boolean;
}

type EmailBody = {
  to?: string;
  name?: string;
  subject?: string;
  text?: string;
  message?: string;
  html?: string;
  company_id?: number | string;
  companyId?: number | string;
  database?: string;
  urls?: string | { url: string; name: string }[];
  attachments?: { name: string; base64?: string }[];
};

@Injectable()
export class EmailService {
  private readonly logger = new Logger(EmailService.name);

  constructor(
    private readonly configService: ConfigService,
    private readonly tenantDatabaseService: TenantDatabaseService,
    private readonly jwtService: JwtService,
  ) {}

  private getDefaultDatabase(): string {
    return (
      this.configService.get<string>('AUTH_DB_NAME') ??
      this.configService.get<string>('DB_NAME') ??
      'railway'
    );
  }

  async getCompanyMailServer(
    database: string | undefined,
    companyId: number,
  ): Promise<CompanyMailServerConfig | null> {
    const db = database || this.getDefaultDatabase();
    try {
      const rows = await this.tenantDatabaseService.query<any>(
        db,
        `SELECT id, company_id, smtp_host, smtp_port, smtp_secure, smtp_user,
                CASE WHEN smtp_pass IS NOT NULL AND smtp_pass <> '' THEN '********' ELSE '' END as smtp_pass,
                from_name, from_email, reply_to, is_active
           FROM public.company_mail_server
          WHERE company_id = $1 AND is_deleted = false
          LIMIT 1`,
        [companyId],
      );
      return rows[0] ?? null;
    } catch (error) {
      this.logger.error(`Error al consultar company_mail_server para empresa ${companyId}:`, error);
      return null;
    }
  }

  async saveCompanyMailServer(
    database: string | undefined,
    companyId: number,
    dto: Partial<CompanyMailServerConfig>,
  ): Promise<CompanyMailServerConfig> {
    const db = database || this.getDefaultDatabase();

    const host = dto.smtp_host?.trim();
    const port = Number(dto.smtp_port ?? 587);
    const secure = Boolean(dto.smtp_secure);
    const user = dto.smtp_user?.trim();
    const pass = dto.smtp_pass ?? '';
    const fromName = dto.from_name?.trim() || user || '';
    const fromEmail = dto.from_email?.trim() || user || '';
    const replyTo = dto.reply_to?.trim() || '';
    const isActive = dto.is_active ?? true;

    if (!host || !user) {
      throw new BadRequestException('El host SMTP y el usuario son obligatorios');
    }

    const sql = `
      INSERT INTO public.company_mail_server (
        company_id, smtp_host, smtp_port, smtp_secure, smtp_user, smtp_pass,
        from_name, from_email, reply_to, is_active, is_deleted, write_date
      ) VALUES (
        $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, false, now()
      )
      ON CONFLICT (company_id) DO UPDATE SET
        smtp_host = EXCLUDED.smtp_host,
        smtp_port = EXCLUDED.smtp_port,
        smtp_secure = EXCLUDED.smtp_secure,
        smtp_user = EXCLUDED.smtp_user,
        smtp_pass = CASE
          WHEN EXCLUDED.smtp_pass <> '' AND EXCLUDED.smtp_pass <> '********'
          THEN EXCLUDED.smtp_pass
          ELSE company_mail_server.smtp_pass
        END,
        from_name = EXCLUDED.from_name,
        from_email = EXCLUDED.from_email,
        reply_to = EXCLUDED.reply_to,
        is_active = EXCLUDED.is_active,
        is_deleted = false,
        write_date = now()
      RETURNING id, company_id, smtp_host, smtp_port, smtp_secure, smtp_user,
                CASE WHEN smtp_pass IS NOT NULL AND smtp_pass <> '' THEN '********' ELSE '' END as smtp_pass,
                from_name, from_email, reply_to, is_active
    `;

    const rows = await this.tenantDatabaseService.query<CompanyMailServerConfig>(
      db,
      sql,
      [companyId, host, port, secure, user, pass, fromName, fromEmail, replyTo, isActive],
    );

    return rows[0];
  }

  async testMailServerConnection(
    config: {
      smtp_host: string;
      smtp_port: number;
      smtp_secure: boolean;
      smtp_user: string;
      smtp_pass: string;
    },
    database?: string,
    companyId?: number,
  ): Promise<{ success: boolean; message: string }> {
    let password = config.smtp_pass;

    // Si la contrasena viene enmascarada y tenemos companyId, recuperamos la real de la BD
    if ((!password || password === '********') && companyId) {
      const db = database || this.getDefaultDatabase();
      const rows = await this.tenantDatabaseService.query<any>(
        db,
        `SELECT smtp_pass FROM public.company_mail_server WHERE company_id = $1 LIMIT 1`,
        [companyId],
      );
      password = rows[0]?.smtp_pass || '';
    }

    if (!password) {
      throw new BadRequestException('Se requiere una contraseña para probar la conexión');
    }

    const transporter = nodemailer.createTransport({
      host: config.smtp_host,
      port: Number(config.smtp_port),
      secure: Boolean(config.smtp_secure),
      auth: {
        user: config.smtp_user,
        pass: password,
      },
      connectionTimeout: 8000,
      greetingTimeout: 8000,
      socketTimeout: 10000,
    });

    try {
      await transporter.verify();
      return { success: true, message: 'Conexión SMTP exitosa con el servidor de correo' };
    } catch (error: any) {
      this.logger.warn(`Fallo prueba SMTP (${config.smtp_user}@${config.smtp_host}): ${error.message}`);
      throw new BadRequestException(`Fallo de conexión SMTP: ${error.message}`);
    }
  }

  private async resolveTransporter(database?: string, companyId?: number) {
    if (companyId && Number(companyId) > 0) {
      const db = database || this.getDefaultDatabase();
      try {
        const rows = await this.tenantDatabaseService.query<any>(
          db,
          `SELECT smtp_host, smtp_port, smtp_secure, smtp_user, smtp_pass, from_name, from_email, reply_to
             FROM public.company_mail_server
            WHERE company_id = $1 AND is_active = true AND is_deleted = false
            LIMIT 1`,
          [Number(companyId)],
        );

        if (rows && rows.length > 0) {
          const cfg = rows[0];
          this.logger.log(`Usando servidor SMTP configurado para empresa ${companyId} (${cfg.smtp_user})`);
          const transporter = nodemailer.createTransport({
            host: cfg.smtp_host,
            port: Number(cfg.smtp_port),
            secure: Boolean(cfg.smtp_secure),
            auth: {
              user: cfg.smtp_user,
              pass: cfg.smtp_pass,
            },
            connectionTimeout: 10000,
            greetingTimeout: 10000,
            socketTimeout: 15000,
          });

          const from = cfg.from_name
            ? `"${cfg.from_name}" <${cfg.from_email || cfg.smtp_user}>`
            : cfg.from_email || cfg.smtp_user;

          return {
            transporter,
            from,
            replyTo: cfg.reply_to || undefined,
          };
        }
      } catch (err) {
        this.logger.error(`Error buscando config de correo de empresa ${companyId}, usando fallback .env:`, err);
      }
    }

    // Fallback al .env global
    this.logger.log('Usando configuración SMTP global (.env)');
    const transporter = nodemailer.createTransport({
      host: this.configService.get<string>('SMTP_HOST') ?? 'smtp.gmail.com',
      port: Number(this.configService.get<string>('SMTP_PORT') ?? 465),
      secure:
        String(this.configService.get<string>('SMTP_SECURE') ?? 'true').toLowerCase() !== 'false',
      auth: {
        user: this.configService.getOrThrow<string>('SMTP_USER'),
        pass: this.configService.getOrThrow<string>('SMTP_PASS'),
      },
      connectionTimeout: Number(
        this.configService.get<string>('SMTP_CONNECTION_TIMEOUT') ?? 10000,
      ),
      greetingTimeout: Number(
        this.configService.get<string>('SMTP_GREETING_TIMEOUT') ?? 10000,
      ),
      socketTimeout: Number(
        this.configService.get<string>('SMTP_SOCKET_TIMEOUT') ?? 15000,
      ),
    });

    return {
      transporter,
      from: this.configService.getOrThrow<string>('SMTP_USER'),
      replyTo: undefined,
    };
  }

  async sendInvoiceEmail(body: EmailBody, files: Express.Multer.File[] = []) {
    const text = body.text ?? body.message;
    if (!body.to || !body.subject || !text) {
      throw new BadRequestException('Faltan campos requeridos: to, subject, text');
    }

    const companyId = body.company_id
      ? Number(body.company_id)
      : body.companyId
      ? Number(body.companyId)
      : undefined;

    const database = body.database;

    const tempFiles: string[] = [];
    const attachments = files.map((file) => ({
      filename: file.originalname,
      path: file.path,
    }));

    try {
      // Soporta adjuntos JSON enviados por /api/send-invoice.
      for (const attachment of body.attachments ?? []) {
        if (!attachment.base64) continue;
        const filePath = this.saveBase64Attachment(attachment);
        tempFiles.push(filePath);
        attachments.push({ filename: attachment.name, path: filePath });
      }

      // Soporta URLs remotas igual que api-rest-s7.
      for (const file of this.parseUrls(body.urls)) {
        const filePath = await this.downloadAttachment(file.url, file.name);
        tempFiles.push(filePath);
        attachments.push({ filename: file.name, path: filePath });
      }

      const { transporter, from, replyTo } = await this.resolveTransporter(database, companyId);

      try {
        await transporter.sendMail({
          from,
          to: body.to,
          replyTo,
          subject: body.subject,
          text,
          html: body.html,
          attachments,
        });
      } catch (smtpError: any) {
        this.logger.error(`Error en servidor SMTP (${from}): ${smtpError.message}`);
        throw new BadRequestException(
          `Error del servidor de correo (${from}): ${smtpError.message || 'Credenciales o servidor rechazó el envío'}`,
        );
      }

      return { success: true, message: 'Email enviado con adjuntos' };
    } finally {
      // Limpia adjuntos temporales generados por multer, base64 o descarga.
      for (const filePath of [...files.map((file) => file.path), ...tempFiles]) {
        if (filePath && fs.existsSync(filePath)) fs.unlinkSync(filePath);
      }
    }
  }

  async sendPasswordResetEmail(body: EmailBody & { resetUrl?: string; userId?: number | string }) {
    if (!body.to && body['email' as keyof typeof body]) {
      body.to = String(body['email' as keyof typeof body]);
    }
    if (!body.to) {
      throw new BadRequestException('Falta el campo requerido: email');
    }

    const email = body.to;
    let resetUrl = body.resetUrl;

    if (!resetUrl && body.userId) {
      const frontendUrl =
        this.configService.get<string>('FRONTEND_URL') ||
        (this.configService.get<string>('CORS_ORIGIN') || '').split(',')[0] ||
        'http://localhost:5173';
      const token = await this.jwtService.signAsync(
        { sub: body.userId, userId: body.userId, email, purpose: 'reset-password', type: 'password-reset' },
        { expiresIn: '1h' },
      );
      resetUrl = `${frontendUrl}/reset-password/${body.userId}/${token}`;
    }

    if (!resetUrl) {
      throw new BadRequestException('Faltan campos requeridos: email y resetUrl');
    }

    const name = String(body['name' as keyof typeof body] || '');
    const greeting = name ? `Hola ${name},` : 'Hola,';

    return this.sendInvoiceEmail({
      to: body.to,
      subject: 'Restablece tu contraseña',
      text: `${greeting}\n\nRecibimos una solicitud para restablecer tu contraseña. Usa el siguiente enlace para continuar:\n${resetUrl}\n\nEste enlace expirará en 1 hora.`,
      html: `
        <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px; border: 1px solid #e2e8f0; border-radius: 8px;">
          <h2 style="color: #0f172a; margin-top: 0;">${greeting}</h2>
          <p style="color: #334155; font-size: 15px;">Recibimos una solicitud para restablecer tu contraseña en el sistema.</p>
          <div style="margin: 24px 0; text-align: center;">
            <a href="${resetUrl}" style="background-color: #121b3c; color: #ffffff; padding: 12px 24px; text-decoration: none; border-radius: 6px; display: inline-block; font-weight: bold; font-size: 14px;">
              Restablecer mi contraseña
            </a>
          </div>
          <p style="color: #64748b; font-size: 13px;">Si no solicitaste este cambio, puedes ignorar este correo con tranquilidad. El enlace expirará en 1 hora.</p>
          <hr style="border: none; border-top: 1px solid #e2e8f0; margin: 20px 0;" />
          <p style="color: #94a3b8; font-size: 12px; margin-bottom: 0;">Este es un mensaje automático, por favor no respondas a este correo.</p>
        </div>
      `,
    });
  }

  async sendUserCredentialsEmail(params: {
    to: string;
    name: string;
    password?: string;
    database?: string;
    companyId?: number;
    verifyToken?: string;
  }) {
    const { to, name, database, companyId, verifyToken } = params;
    const greeting = name ? `Hola ${name},` : 'Hola,';
    const frontendUrl =
      this.configService.get<string>('FRONTEND_URL') ||
      (this.configService.get<string>('CORS_ORIGIN') || '').split(',')[0] ||
      'http://localhost:5173';

    const verifyUrl = verifyToken
      ? `${frontendUrl}/verify-email?token=${verifyToken}`
      : `${frontendUrl}/auth`;

    const text = `${greeting}\n\n` +
      `Se ha creado tu cuenta de usuario para acceder a S7 ERP.\n\n` +
      `Para activar tu cuenta y configurar tu contraseña de acceso, por favor ingresa al siguiente enlace:\n` +
      `${verifyUrl}\n\n` +
      `Usuario / Correo: ${to}\n\n` +
      `Saludos cordiales,\nEquipo de Administración.`;

    const html = `
      <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 24px; border: 1px solid #e2e8f0; border-radius: 8px; background-color: #ffffff;">
        <h2 style="color: #0f172a; margin-top: 0; font-size: 20px;">¡Bienvenido(a) a S7 ERP!</h2>
        <p style="color: #334155; font-size: 15px; line-height: 1.5;">${greeting}</p>
        <p style="color: #334155; font-size: 14px; line-height: 1.5;">Se ha creado tu cuenta de acceso a la plataforma. Para completar tu registro y activar tu cuenta, por favor haz clic en el siguiente botón para establecer tu contraseña personal:</p>
        
        <div style="margin: 28px 0; text-align: center;">
          <a href="${verifyUrl}" style="background-color: #121b3c; color: #ffffff; padding: 14px 28px; text-decoration: none; border-radius: 6px; display: inline-block; font-weight: bold; font-size: 15px; letter-spacing: 0.5px;">
            Activar cuenta y configurar contraseña
          </a>
        </div>

        <div style="background-color: #f8fafc; border-left: 4px solid #121b3c; padding: 12px 16px; margin: 20px 0; border-radius: 4px;">
          <p style="margin: 0; color: #475569; font-size: 13px;"><strong>Usuario / Correo asignado:</strong> <span style="color: #1e293b;">${to}</span></p>
        </div>

        <p style="color: #64748b; font-size: 13px; line-height: 1.4;">Si el botón no funciona, también puedes copiar y pegar el siguiente enlace en tu navegador:<br />
          <a href="${verifyUrl}" style="color: #2563eb; word-break: break-all;">${verifyUrl}</a>
        </p>

        <hr style="border: none; border-top: 1px solid #e2e8f0; margin: 24px 0;" />
        <p style="color: #94a3b8; font-size: 12px; margin-bottom: 0;">Este es un mensaje automático de seguridad, por favor no responda directamente a este correo.</p>
      </div>
    `;

    return this.sendInvoiceEmail({
      to,
      subject: '¡Bienvenido(a) a S7 ERP! Activa tu cuenta',
      text,
      html,
      database,
      companyId,
    });
  }

  private parseUrls(rawUrls: EmailBody['urls']) {
    if (!rawUrls) return [];
    if (Array.isArray(rawUrls)) return rawUrls;
    try {
      return JSON.parse(rawUrls) as { url: string; name: string }[];
    } catch {
      return [];
    }
  }

  private saveBase64Attachment(attachment: { name: string; base64?: string }) {
    const [, data = attachment.base64 ?? ''] =
      attachment.base64?.split(',') ?? [];
    const filePath = path.join('uploads', `${Date.now()}-${attachment.name}`);
    fs.mkdirSync(path.dirname(filePath), { recursive: true });
    fs.writeFileSync(filePath, Buffer.from(data, 'base64'));
    return filePath;
  }

  private async downloadAttachment(url: string, name: string) {
    const response = await fetch(url);
    if (!response.ok) throw new Error(`Error descargando ${name}`);

    const filePath = path.join('uploads', `${Date.now()}-${name}`);
    fs.mkdirSync(path.dirname(filePath), { recursive: true });
    fs.writeFileSync(filePath, Buffer.from(await response.arrayBuffer()));
    return filePath;
  }
}
