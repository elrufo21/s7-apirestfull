import {
  BadRequestException,
  Controller,
  Delete,
  Get,
  Param,
  Post,
  Req,
  UploadedFile,
  UseGuards,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { randomUUID } from 'crypto';
import { existsSync, mkdirSync } from 'fs';
import { diskStorage } from 'multer';
import { extname, join } from 'path';

import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import type { AuthenticatedRequest } from '../auth/jwt-auth.guard';
import { FilesService } from './files.service';

@Controller('files')
@UseGuards(JwtAuthGuard)
export class FilesController {
  constructor(private readonly filesService: FilesService) {}

  @Get('images')
  async listImages(@Req() req: AuthenticatedRequest) {
    return {
      ok: true,
      files: await this.filesService.listImages(req.user.groupId),
    };
  }

  @Post('images')
  @UseInterceptors(
    FileInterceptor('file', {
      storage: diskStorage({
        destination: (req: AuthenticatedRequest, _file, callback) => {
          const basePath =
            process.env.STORAGE_PATH ?? join(process.cwd(), 'storage');
          const targetDir = join(
            basePath,
            `product-images-${req.user.groupId}`,
          );

          if (!existsSync(targetDir)) {
            mkdirSync(targetDir, { recursive: true });
          }

          callback(null, targetDir);
        },
        filename: (_request, file, callback) => {
          callback(
            null,
            `${randomUUID()}${extname(file.originalname).toLowerCase()}`,
          );
        },
      }),
      limits: { fileSize: 5 * 1024 * 1024 },
      fileFilter: (_request, file, callback) => {
        const allowedMimeTypes = ['image/jpeg', 'image/png', 'image/webp'];

        if (!allowedMimeTypes.includes(file.mimetype)) {
          return callback(
            new BadRequestException(
              'Solo se permiten imágenes JPG, PNG o WEBP.',
            ),
            false,
          );
        }

        callback(null, true);
      },
    }),
  )
  uploadImage(
    @Req() req: AuthenticatedRequest,
    @UploadedFile() file?: Express.Multer.File,
  ) {
    if (!file) {
      throw new BadRequestException('No se recibió ningún archivo.');
    }

    return {
      ok: true,
      filename: file.filename,
      url: this.filesService.getPublicPath(req.user.groupId, file.filename),
      size: file.size,
      mimetype: file.mimetype,
    };
  }

  @Delete('images/:filename')
  async deleteImage(
    @Req() req: AuthenticatedRequest,
    @Param('filename') filename: string,
  ) {
    return {
      ok: true,
      ...(await this.filesService.deleteImageGlobally({
        database: req.user.database,
        filename,
        groupId: req.user.groupId,
      })),
    };
  }
}
