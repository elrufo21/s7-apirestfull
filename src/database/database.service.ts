import { Injectable, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Pool, QueryResultRow } from 'pg';

@Injectable()
export class DatabaseService implements OnModuleInit, OnModuleDestroy {
  private readonly pool: Pool;
  constructor(private readonly configService: ConfigService) {
    this.pool = new Pool({
      host: this.configService.getOrThrow('DB_HOST'),
      port: this.configService.getOrThrow('DB_PORT'),
      user: this.configService.getOrThrow('DB_USER'),
      password: this.configService.getOrThrow('DB_PASSWORD'),
      database: this.configService.getOrThrow('DB_NAME'),
      max: 10,
      idleTimeoutMillis: 3_000,
      connectionTimeoutMillis: 5_000,
    });
  }
  async onModuleInit(): Promise<void> {
    const conection = await this.pool.connect();
    try {
      await conection.query('SELECT 1');
      console.log('Database connection established successfully.');
    } catch (error) {
      console.error('Error connecting to the database:', error);
    } finally {
      conection.release();
    }
  }
  async query<T extends QueryResultRow>(
    sql: string,
    parameters: unknown[] = [],
  ): Promise<T[]> {
    const result = await this.pool.query<T>(sql, parameters);
    return result.rows;
  }

  async onModuleDestroy(): Promise<void> {
    await this.pool.end();
  }
}
