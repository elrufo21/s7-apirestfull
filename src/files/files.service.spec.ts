import { Test, TestingModule } from '@nestjs/testing';
import { BadRequestException } from '@nestjs/common';
import { mkdtemp, mkdir, rm, writeFile } from 'fs/promises';
import { tmpdir } from 'os';
import { join } from 'path';

import { TenantDatabaseService } from '../tenant-database/tenant-database.service';
import { FilesService } from './files.service';

describe('FilesService', () => {
  let service: FilesService;
  let storagePath: string;
  const query = jest.fn();

  beforeEach(async () => {
    storagePath = await mkdtemp(join(tmpdir(), 's7-product-images-'));
    process.env.STORAGE_PATH = storagePath;
    query.mockReset();
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        FilesService,
        { provide: TenantDatabaseService, useValue: { query } },
      ],
    }).compile();

    service = module.get<FilesService>(FilesService);
  });

  afterEach(async () => {
    delete process.env.STORAGE_PATH;
    await rm(storagePath, { recursive: true, force: true });
  });

  it('should be defined', () => {
    expect(service).toBeDefined();
  });

  it('removes the references before deleting the client file', async () => {
    const folder = join(storagePath, 'product-images-7');
    await mkdir(folder);
    await writeFile(join(folder, 'sample.webp'), 'image');
    query.mockResolvedValue([{ product_count: '2', template_count: '3' }]);

    await expect(
      service.deleteImageGlobally({
        database: 'tenant',
        filename: 'sample.webp',
        groupId: 7,
      }),
    ).resolves.toEqual({
      filename: 'sample.webp',
      affectedProducts: 2,
      affectedTemplates: 3,
    });

    expect(query).toHaveBeenCalledWith(
      'tenant',
      expect.stringContaining('UPDATE public.product_template'),
      [7, 'sample.webp', '/sample.webp'],
    );
    await expect(service.listImages(7)).resolves.toEqual([]);
  });

  it('rejects paths outside the client image folder', async () => {
    await expect(
      service.deleteImageGlobally({
        database: 'tenant',
        filename: '../sample.webp',
        groupId: 7,
      }),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(query).not.toHaveBeenCalled();
  });
});
