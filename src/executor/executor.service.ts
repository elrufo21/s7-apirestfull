import { Injectable, InternalServerErrorException } from '@nestjs/common';

import { TenantDatabaseService } from '../tenant-database/tenant-database.service';
import { ExecuteDto } from './dto/execute.dto';
import type { JwtPayload } from '../auth/jwt-auth.guard';

@Injectable()
export class ExecutorService {
  constructor(private readonly tenantDatabaseService: TenantDatabaseService) {}

  async execute(dto: ExecuteDto, authenticatedUser: JwtPayload) {
    const userId = authenticatedUser.userId ?? dto.userId;
    const groupId = authenticatedUser.groupId ?? dto.groupId;

    const database = authenticatedUser.database;

    const companies = dto.companies ?? [];
    const action = dto.action ?? '';
    const data = dto.data ?? [];

    if (!userId) {
      throw new InternalServerErrorException(
        'No se pudo determinar el usuario',
      );
    }

    if (!groupId) {
      throw new InternalServerErrorException(
        'No se pudo determinar el grupo del usuario',
      );
    }

    const rows = await this.tenantDatabaseService.query(
      database,
      `
        SELECT *
        FROM public.fnc_execute(
          $1::text,
          $2::integer,
          $3::integer,
          $4::jsonb,
          $5::text,
          $6::jsonb
        )
      `,
      [
        dto.functionName,
        userId,
        groupId,
        JSON.stringify(companies),
        action,
        JSON.stringify(data),
      ],
    );

    return rows;
  }
}
