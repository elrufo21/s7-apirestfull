import {
  Body,
  Controller,
  Get,
  Param,
  Post,
  Req,
  UploadedFiles,
  UseInterceptors,
} from '@nestjs/common';
import { FilesInterceptor } from '@nestjs/platform-express';
import { diskStorage } from 'multer';
import { CompanyMailServerConfig, EmailService } from './email.service';
import type { Request } from 'express';

@Controller()
export class EmailController {
  constructor(private readonly emailService: EmailService) {}

  @Post('email/send')
  @UseInterceptors(
    FilesInterceptor('attachments', 20, {
      storage: diskStorage({ destination: 'uploads' }),
    }),
  )
  send(
    @Body() body: Record<string, unknown>,
    @UploadedFiles() files: Express.Multer.File[] = [],
  ) {
    // Endpoint usado por el modal de envio de comprobantes.
    return this.emailService.sendInvoiceEmail(body, files);
  }

  @Post('send-invoice')
  sendInvoice(@Body() body: Record<string, unknown>) {
    // Compatibilidad con el fetch viejo a /api/send-invoice.
    return this.emailService.sendInvoiceEmail(body);
  }

  @Post('auth/password/reset-email')
  resetPassword(@Body() body: Record<string, unknown>) {
    // Endpoint usado por RecoverPassword para enviar enlace de recuperacion.
    return this.emailService.sendPasswordResetEmail(body);
  }

  @Get('email/company/:companyId')
  async getCompanyMailServer(
    @Param('companyId') companyId: string,
    @Req() req: Request,
  ) {
    const database = (req as any).user?.database;
    const config = await this.emailService.getCompanyMailServer(
      database,
      Number(companyId),
    );
    return { success: true, data: config };
  }

  @Post('email/company/:companyId')
  async saveCompanyMailServer(
    @Param('companyId') companyId: string,
    @Body() body: Partial<CompanyMailServerConfig>,
    @Req() req: Request,
  ) {
    const database = (req as any).user?.database;
    const config = await this.emailService.saveCompanyMailServer(
      database,
      Number(companyId),
      body,
    );
    return {
      success: true,
      message: 'Configuración de correo guardada con éxito',
      data: config,
    };
  }

  @Post('email/company/:companyId/test')
  async testCompanyMailServer(
    @Param('companyId') companyId: string,
    @Body()
    body: {
      smtp_host: string;
      smtp_port: number;
      smtp_secure: boolean;
      smtp_user: string;
      smtp_pass: string;
    },
    @Req() req: Request,
  ) {
    const database = (req as any).user?.database;
    return this.emailService.testMailServerConnection(
      body,
      database,
      Number(companyId),
    );
  }
}
