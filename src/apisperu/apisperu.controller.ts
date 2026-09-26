import {
  Controller,
  Get,
  Post,
  Req,
  Res,
  Query,
} from '@nestjs/common';
import type { Request, Response } from 'express';
import { ApisPeruService } from './apisperu.service';

@Controller('apisperu')
export class ApisPeruController {
  constructor(private readonly apisPeruService: ApisPeruService) {}

  /**
   * Endpoint compatible con factura-builder pero canalizado a través de APIs Perú
   */
  @Post('factura-builder')
  async facturaBuilder(@Req() req: Request, @Res() res: Response) {
    try {
      const customToken = (req.headers['x-apisperu-token'] as string) || undefined;
      const result = await this.apisPeruService.processInvoice(
        req.body,
        false,
        customToken,
      );
      return res.status(200).json(result);
    } catch (error: any) {
      const status = error.statusCode || error.status || 500;
      return res.status(status).json({
        success: false,
        flow: 'apisperu_builder',
        message: error.message || 'Error procesando factura con APIs Perú',
        ...(error.sunatCode ? { sunatCode: error.sunatCode } : {}),
        ...(error.details ? { details: error.details } : {}),
      });
    }
  }

  /**
   * Endpoint compatible con boleta-builder pero canalizado a través de APIs Perú
   */
  @Post('boleta-builder')
  async boletaBuilder(@Req() req: Request, @Res() res: Response) {
    try {
      const customToken = (req.headers['x-apisperu-token'] as string) || undefined;
      const result = await this.apisPeruService.processInvoice(
        req.body,
        true,
        customToken,
      );
      return res.status(200).json(result);
    } catch (error: any) {
      const status = error.statusCode || error.status || 500;
      return res.status(status).json({
        success: false,
        flow: 'apisperu_builder',
        message: error.message || 'Error procesando boleta con APIs Perú',
        ...(error.sunatCode ? { sunatCode: error.sunatCode } : {}),
        ...(error.details ? { details: error.details } : {}),
      });
    }
  }

  /**
   * Generación y descarga directa del PDF oficial renderizado por APIs Perú
   */
  @Post('pdf')
  async generatePdf(@Req() req: Request, @Res() res: Response) {
    try {
      const customToken = (req.headers['x-apisperu-token'] as string) || undefined;
      const isBoleta = Boolean(
        req.query.tipo === '03' ||
        req.body?.tipoDoc === '03' ||
        String(req.body?.name || '').startsWith('B'),
      );
      const pdfBuffer = await this.apisPeruService.getInvoicePdf(
        req.body,
        isBoleta,
        customToken,
      );

      res.setHeader('Content-Type', 'application/pdf');
      res.setHeader(
        'Content-Disposition',
        `inline; filename="comprobante-${Date.now()}.pdf"`,
      );
      return res.send(pdfBuffer);
    } catch (error: any) {
      const status = error.statusCode || error.status || 500;
      return res.status(status).json({
        success: false,
        message: error.message || 'Error generando PDF en APIs Perú',
      });
    }
  }

  /**
   * Consulta de estado del comprobante ante SUNAT
   */
  @Get('status')
  async getStatus(
    @Query('tipo') tipo: string,
    @Query('serie') serie: string,
    @Query('numero') numero: string,
    @Query('ruc') ruc: string,
    @Req() req: Request,
    @Res() res: Response,
  ) {
    try {
      const customToken = (req.headers['x-apisperu-token'] as string) || undefined;
      const result = await this.apisPeruService.getInvoiceStatus({
        tipo,
        serie,
        numero,
        ruc,
        customToken,
      });
      return res.status(200).json(result);
    } catch (error: any) {
      const status = error.statusCode || error.status || 500;
      return res.status(status).json({
        success: false,
        message: error.message || 'Error consultando estado en APIs Perú',
      });
    }
  }
}
