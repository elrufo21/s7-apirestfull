import { BadRequestException, Injectable } from '@nestjs/common';
import { existsSync } from 'fs';
import { readdir, stat, unlink } from 'fs/promises';
import { extname, join } from 'path';

import { TenantDatabaseService } from '../tenant-database/tenant-database.service';

const IMAGE_EXTENSIONS = new Set(['.jpg', '.jpeg', '.png', '.webp']);

@Injectable()
export class FilesService {
  constructor(private readonly tenantDatabaseService: TenantDatabaseService) {}

  getFolderName(groupId: number) {
    return `product-images-${groupId}`;
  }

  getStorageDirectory(groupId: number) {
    const basePath = process.env.STORAGE_PATH ?? join(process.cwd(), 'storage');
    return join(basePath, this.getFolderName(groupId));
  }

  getPublicPath(groupId: number, filename: string) {
    return `/storage/${this.getFolderName(groupId)}/${filename}`;
  }

  async listImages(groupId: number) {
    const targetDir = this.getStorageDirectory(groupId);

    if (!existsSync(targetDir)) {
      return [];
    }

    const entries = await readdir(targetDir, { withFileTypes: true });
    const files = await Promise.all(
      entries
        .filter(
          (entry) =>
            entry.isFile() &&
            IMAGE_EXTENSIONS.has(extname(entry.name).toLowerCase()),
        )
        .map(async (entry) => {
          const stats = await stat(join(targetDir, entry.name));
          const publicPath = this.getPublicPath(groupId, entry.name);

          return {
            filename: entry.name,
            url: publicPath,
            path: publicPath,
            publicUrl: publicPath,
            size: stats.size,
            createdAt: stats.birthtime,
            modifiedAt: stats.mtime,
          };
        }),
    );

    return files.sort(
      (a, b) => b.modifiedAt.getTime() - a.modifiedAt.getTime(),
    );
  }

  async deleteImageGlobally({
    database,
    filename,
    groupId,
  }: {
    database: string;
    filename: string;
    groupId: number;
  }) {
    this.validateFilename(filename);

    const pathSuffix = `/${filename}`;
    const rows = await this.tenantDatabaseService.query<{
      product_count: string;
      template_count: string;
    }>(
      database,
      `
        WITH template_updates AS (
          UPDATE public.product_template AS pt
          SET files = (
            SELECT CASE
              WHEN COUNT(*) = 0 THEN NULL
              ELSE jsonb_agg(image ORDER BY position)
            END
            FROM jsonb_array_elements(
              CASE WHEN jsonb_typeof(pt.files) = 'array'
                THEN pt.files ELSE '[]'::jsonb END
            ) WITH ORDINALITY AS images(image, position)
            WHERE NOT (
              image->>'filename' = $2
              OR RIGHT(COALESCE(image->>'path', ''), LENGTH($3)) = $3
              OR RIGHT(COALESCE(image->>'url', ''), LENGTH($3)) = $3
              OR RIGHT(COALESCE(image->>'publicUrl', ''), LENGTH($3)) = $3
            )
          )
          WHERE pt.group_id = $1
            AND EXISTS (
              SELECT 1
              FROM jsonb_array_elements(
                CASE WHEN jsonb_typeof(pt.files) = 'array'
                  THEN pt.files ELSE '[]'::jsonb END
              ) AS current_images(image)
              WHERE image->>'filename' = $2
                OR RIGHT(COALESCE(image->>'path', ''), LENGTH($3)) = $3
                OR RIGHT(COALESCE(image->>'url', ''), LENGTH($3)) = $3
                OR RIGHT(COALESCE(image->>'publicUrl', ''), LENGTH($3)) = $3
            )
          RETURNING pt.product_template_id
        ),
        product_updates AS (
          UPDATE public.product AS product
          SET files = (
            SELECT CASE
              WHEN COUNT(*) = 0 THEN NULL
              ELSE jsonb_agg(image ORDER BY position)
            END
            FROM jsonb_array_elements(
              CASE WHEN jsonb_typeof(product.files) = 'array'
                THEN product.files ELSE '[]'::jsonb END
            ) WITH ORDINALITY AS images(image, position)
            WHERE NOT (
              image->>'filename' = $2
              OR RIGHT(COALESCE(image->>'path', ''), LENGTH($3)) = $3
              OR RIGHT(COALESCE(image->>'url', ''), LENGTH($3)) = $3
              OR RIGHT(COALESCE(image->>'publicUrl', ''), LENGTH($3)) = $3
            )
          )
          WHERE product.group_id = $1
            AND EXISTS (
              SELECT 1
              FROM jsonb_array_elements(
                CASE WHEN jsonb_typeof(product.files) = 'array'
                  THEN product.files ELSE '[]'::jsonb END
              ) AS current_images(image)
              WHERE image->>'filename' = $2
                OR RIGHT(COALESCE(image->>'path', ''), LENGTH($3)) = $3
                OR RIGHT(COALESCE(image->>'url', ''), LENGTH($3)) = $3
                OR RIGHT(COALESCE(image->>'publicUrl', ''), LENGTH($3)) = $3
            )
          RETURNING product.product_id
        )
        SELECT
          (SELECT COUNT(*) FROM template_updates)::text AS template_count,
          (SELECT COUNT(*) FROM product_updates)::text AS product_count
      `,
      [groupId, filename, pathSuffix],
    );

    try {
      await unlink(join(this.getStorageDirectory(groupId), filename));
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== 'ENOENT') {
        throw error;
      }
    }

    return {
      filename,
      affectedProducts: Number(rows[0]?.product_count ?? 0),
      affectedTemplates: Number(rows[0]?.template_count ?? 0),
    };
  }

  private validateFilename(filename: string) {
    if (
      !filename ||
      filename.includes('/') ||
      filename.includes('\\') ||
      !IMAGE_EXTENSIONS.has(extname(filename).toLowerCase())
    ) {
      throw new BadRequestException('Nombre de imagen inválido.');
    }
  }
}
