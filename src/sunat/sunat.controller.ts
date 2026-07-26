import {
  Body,
  Controller,
  Next,
  Post,
  Req,
  Res,
  UploadedFile,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { diskStorage } from 'multer';
import type { NextFunction, Request, Response } from 'express';

import {
  deleteFileToDrive,
  enviarBoletaBuilder,
  enviarFactura,
  enviarFacturaBuilder,
  enviarFacturaPrueba,
  enviarNotaCreditoBuilder,
  enviarNotaDebitoBuilder,
  uploadSunatCertificate,
} from './legacy/sunat.controller.legacy';

@Controller('sunat')
export class SunatController {
  @Post('factura')
  factura(@Req() req: Request, @Res() res: Response, @Next() next: NextFunction) {
    // Reusa la logica fiscal ya probada del backend Express anterior.
    return enviarFactura(req, res, next);
  }

  @Post('factura-prueba')
  facturaPrueba(
    @Req() req: Request,
    @Res() res: Response,
    @Next() next: NextFunction,
  ) {
    // Mantiene endpoint de prueba SUNAT para diagnósticos.
    return enviarFacturaPrueba(req, res, next);
  }

  @Post('factura-builder')
  facturaBuilder(
    @Req() req: Request,
    @Res() res: Response,
    @Next() next: NextFunction,
  ) {
    // Endpoint usado por el front para facturas electronicas.
    return enviarFacturaBuilder(req, res, next);
  }

  @Post('boleta-builder')
  boletaBuilder(
    @Req() req: Request,
    @Res() res: Response,
    @Next() next: NextFunction,
  ) {
    // Endpoint usado por el front para boletas electronicas.
    return enviarBoletaBuilder(req, res, next);
  }

  @Post('nota-credito-builder')
  notaCreditoBuilder(
    @Req() req: Request,
    @Res() res: Response,
    @Next() next: NextFunction,
  ) {
    // Endpoint usado cuando el comprobante es nota de credito.
    return enviarNotaCreditoBuilder(req, res, next);
  }

  @Post('nota-debito-builder')
  notaDebitoBuilder(
    @Req() req: Request,
    @Res() res: Response,
    @Next() next: NextFunction,
  ) {
    // Endpoint usado cuando el comprobante es nota de debito.
    return enviarNotaDebitoBuilder(req, res, next);
  }

  @Post('certificado')
  @UseInterceptors(
    FileInterceptor('certificado', {
      storage: diskStorage({ destination: 'uploads' }),
    }),
  )
  certificado(
    @UploadedFile() file: Express.Multer.File,
    @Body() body: Record<string, unknown>,
    @Req() req: Request,
    @Res() res: Response,
    @Next() next: NextFunction,
  ) {
    // Adapta multer de Nest al shape req.file esperado por el codigo legado.
    (req as Request & { file?: Express.Multer.File }).file = file;
    req.body = body;
    return uploadSunatCertificate(req, res, next);
  }

  @Post('deleteFileToDrive')
  deleteFile(
    @Req() req: Request,
    @Res() res: Response,
    @Next() next: NextFunction,
  ) {
    // Nombre historico del front; realmente elimina en Cloudflare R2.
    return deleteFileToDrive(req, res, next);
  }
}
