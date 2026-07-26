import { Injectable, InternalServerErrorException } from '@nestjs/common';

import { TenantDatabaseService } from '../tenant-database/tenant-database.service';
import type { UserDataProcedureResult } from './user-data.types';

@Injectable()
export class UserDataService {
  constructor(private readonly tenantDatabaseService: TenantDatabaseService) {}

  async findByUser(
    database: string,
    userId: number,
  ): Promise<UserDataProcedureResult> {
    const rows =
      await this.tenantDatabaseService.query<UserDataProcedureResult>(
        database,
        `
          SELECT oj_info, oj_data
          FROM public.fnc_user_data($1::integer)
        `,
        [userId],
      );

    const result = rows[0];

    if (!result) {
      throw new InternalServerErrorException(
        'fnc_user_data no devolvió una respuesta',
      );
    }

    return result;
  }
}
