import {
  Body,
  Controller,
  Post,
  UploadedFiles,
  UseInterceptors,
} from '@nestjs/common';
import { FilesInterceptor } from '@nestjs/platform-express';
import { diskStorage } from 'multer';
import { EmailService } from './email.service';

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
}
