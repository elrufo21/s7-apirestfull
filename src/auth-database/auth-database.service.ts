import {
  Injectable,
  Logger,
  OnModuleDestroy,
  OnModuleInit,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Pool, QueryResultRow } from 'pg';

@Injectable()
export class AuthDatabaseService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(AuthDatabaseService.name);
  private readonly pool: Pool;

  constructor(private readonly configService: ConfigService) {
    this.pool = new Pool({
      host: this.configService.get<string>('AUTH_DB_HOST') || '169.58.105.101',
      port: Number(this.configService.get<string>('AUTH_DB_PORT') || 5432),
      user: this.configService.get<string>('AUTH_DB_USER') || 'postgres',
      password: this.configService.get<string>('AUTH_DB_PASSWORD') || 'linksoft2026',
      database: this.configService.get<string>('AUTH_DB_NAME') || 's7_auth',

      // Máximo de conexiones abiertas hacia la base central.
      max: 10,

      // Cierra conexiones inactivas después de 30 segundos.
      idleTimeoutMillis: 30_000,

      // Tiempo máximo para intentar conectarse.
      connectionTimeoutMillis: 5_000,
    });
  }

  async onModuleInit(): Promise<void> {
    try {
      await this.pool.query('SELECT 1');

      this.logger.log(
        'Conexión establecida con la base central de autenticación',
      );
    } catch (error) {
      this.logger.error(
        'No se pudo conectar a la base central de autenticación',
        error instanceof Error ? error.stack : String(error),
      );

      throw error;
    }
  }

  async onModuleDestroy(): Promise<void> {
    await this.pool.end();
  }

  async query<T extends QueryResultRow = QueryResultRow>(
    sql: string,
    parameters: unknown[] = [],
  ): Promise<T[]> {
    const result = await this.pool.query<T>(sql, parameters);

    return result.rows;
  }
}
