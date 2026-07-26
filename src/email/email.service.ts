import { BadRequestException, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import fs from 'node:fs';
import path from 'node:path';
import nodemailer from 'nodemailer';

type EmailBody = {
  to?: string;
  subject?: string;
  text?: string;
  message?: string;
  html?: string;
  urls?: string | { url: string; name: string }[];
  attachments?: { name: string; base64?: string }[];
};

@Injectable()
export class EmailService {
  constructor(private readonly configService: ConfigService) {}

  private getTransporter() {
    // Crea el transporter con la misma configuracion SMTP del backend Express viejo.
    return nodemailer.createTransport({
      host: this.configService.get<string>('SMTP_HOST') ?? 'smtp.gmail.com',
      port: Number(this.configService.get<string>('SMTP_PORT') ?? 465),
      secure: String(
        this.configService.get<string>('SMTP_SECURE') ?? 'true',
      ).toLowerCase() !== 'false',
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
  }

  async sendInvoiceEmail(body: EmailBody, files: Express.Multer.File[] = []) {
    const text = body.text ?? body.message;
    if (!body.to || !body.subject || !text) {
      throw new BadRequestException(
        'Faltan campos requeridos: to, subject, text',
      );
    }

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

      await this.getTransporter().sendMail({
        from: this.configService.getOrThrow<string>('SMTP_USER'),
        to: body.to,
        subject: body.subject,
        text,
        html: body.html,
        attachments,
      });

      return { success: true, message: 'Email enviado con adjuntos' };
    } finally {
      // Limpia adjuntos temporales generados por multer, base64 o descarga.
      for (const filePath of [...files.map((file) => file.path), ...tempFiles]) {
        if (filePath && fs.existsSync(filePath)) fs.unlinkSync(filePath);
      }
    }
  }

  async sendPasswordResetEmail(body: EmailBody & { resetUrl?: string }) {
    if (!body.to && body['email' as keyof typeof body]) {
      body.to = String(body['email' as keyof typeof body]);
    }
    if (!body.to || !body.resetUrl) {
      throw new BadRequestException(
        'Faltan campos requeridos: email y resetUrl',
      );
    }

    const name = String(body['name' as keyof typeof body] || '');
    const greeting = name ? `Hola ${name},` : 'Hola,';

    // Plantilla minima, misma finalidad que el backend anterior.
    return this.sendInvoiceEmail({
      to: body.to,
      subject: 'Restablece tu contrasena',
      text: `${greeting}\n\nRecibimos una solicitud para restablecer tu contrasena. Usa el siguiente enlace para continuar:\n${body.resetUrl}`,
      html: `<p>${greeting}</p><p>Recibimos una solicitud para restablecer tu contrasena.</p><p><a href="${body.resetUrl}">Cambiar contrasena</a></p>`,
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
