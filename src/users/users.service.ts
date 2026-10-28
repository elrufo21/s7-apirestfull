import {
  BadRequestException,
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';

import { AuthDatabaseService } from '../auth-database/auth-database.service';
import type { JwtPayload } from '../auth/jwt-auth.guard';
import { EmailService } from '../email/email.service';
import { TenantDatabaseService } from '../tenant-database/tenant-database.service';
import { CreateUserDto } from './dto/create-user.dto';
import { UpdateUserDto } from './dto/update-user.dto';

const defaultPassword = (name: string) =>
  name
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/\s+/g, '')
    .toLowerCase() || 'usuario';

@Injectable()
export class UsersService {
  private readonly logger = new Logger(UsersService.name);

  constructor(
    private readonly authDatabaseService: AuthDatabaseService,
    private readonly emailService: EmailService,
    private readonly tenantDatabaseService: TenantDatabaseService,
    private readonly jwtService: JwtService,
  ) {}

  async create(dto: CreateUserDto, user: JwtPayload) {
    const generatedPassword = defaultPassword(dto.name);

    const created = await this.authDatabaseService.query<{ created: boolean }>(
      'SELECT public.fnc_create_user($1, $2, $3, $4, $5, $6) AS created',
      [
        user.groupId,
        dto.state.trim(),
        dto.name.trim(),
        dto.email.trim().toLowerCase(),
        generatedPassword,
        user.database,
      ],
    );

    if (!created[0]?.created) {
      throw new BadRequestException('No se pudo crear el usuario');
    }

    const userRow = await this.authDatabaseService.query<{ user_id: number }>(
      'SELECT user_id FROM public."user" WHERE lower(email) = lower($1) AND group_id = $2 LIMIT 1',
      [dto.email.trim().toLowerCase(), user.groupId],
    );

    let verifyToken: string | undefined;
    if (userRow[0]?.user_id) {
      try {
        verifyToken = await this.jwtService.signAsync(
          {
            sub: userRow[0].user_id,
            userId: userRow[0].user_id,
            email: dto.email.trim().toLowerCase(),
            database: user.database,
            purpose: 'verify-email',
            type: 'email-verification',
          },
          { expiresIn: '7d' },
        );
      } catch (err) {
        this.logger.warn(`No se pudo firmar token de verificación: ${err}`);
      }
    }

    // Enviar correo con credenciales de acceso usando el servidor de correo configurado
    try {
      await this.emailService.sendUserCredentialsEmail({
        to: dto.email.trim().toLowerCase(),
        name: dto.name.trim(),
        password: generatedPassword,
        database: user.database,
        verifyToken,
      });
      this.logger.log(`Correo de credenciales enviado con éxito a ${dto.email}`);
    } catch (mailError: any) {
      this.logger.error(
        `Usuario creado pero no se pudo enviar correo a ${dto.email}: ${mailError?.message || mailError}`,
      );
    }

    return {
      success: true,
      message: 'Usuario creado correctamente',
      user_id: userRow[0]?.user_id ?? null,
    };
  }

  async update(userId: number, dto: UpdateUserDto, user: JwtPayload) {
    const ownedUser = await this.authDatabaseService.query<{ user_id: number }>(
      'SELECT user_id FROM public."user" WHERE (user_id = $1 OR lower(email) = lower($2)) AND group_id = $3 LIMIT 1',
      [userId, dto.email.trim(), user.groupId],
    );

    if (!ownedUser[0]?.user_id) {
      throw new NotFoundException('Usuario no encontrado');
    }

    const targetUserId = ownedUser[0].user_id;

    const updated = await this.authDatabaseService.query<{ updated: boolean }>(
      'SELECT public.fnc_update_user($1, $2, $3, $4) AS updated',
      [
        targetUserId,
        dto.state.trim(),
        dto.name.trim(),
        dto.email.trim().toLowerCase(),
      ],
    );

    if (!updated[0]?.updated) {
      throw new BadRequestException('No se pudo actualizar el usuario');
    }

    return { success: true, message: 'Usuario actualizado correctamente' };
  }

  async resendInvite(
    target: string,
    user: JwtPayload,
    body?: { email?: string; user_id?: number | string; partner_id?: number | string },
  ) {
    const rawTarget = String(target || '').trim();
    const emailCandidate = (body?.email || (rawTarget.includes('@') ? rawTarget : '')).trim().toLowerCase();

    let userRow: { user_id: number; email: string; password?: string; name: string } | null = null;

    // 1. Buscar por email si está disponible
    if (emailCandidate) {
      const rows = await this.authDatabaseService.query<any>(
        'SELECT user_id, email, password, name FROM public."user" WHERE lower(email) = lower($1) AND group_id = $2 LIMIT 1',
        [emailCandidate, user.groupId],
      );
      if (rows.length > 0) {
        userRow = rows[0];
      }
    }

    // 2. Si no se encontró por email, intentar por user_id numérico
    const numericId = Number(body?.user_id || (!Number.isNaN(Number(rawTarget)) ? Number(rawTarget) : null));
    if (!userRow && numericId) {
      const rows = await this.authDatabaseService.query<any>(
        'SELECT user_id, email, password, name FROM public."user" WHERE user_id = $1 AND group_id = $2 LIMIT 1',
        [numericId, user.groupId],
      );
      if (rows.length > 0) {
        userRow = rows[0];
      }
    }

    // 3. Si aún no se encuentra, buscar por partner_id en el tenant
    const partnerId = Number(body?.partner_id || (!Number.isNaN(Number(rawTarget)) ? Number(rawTarget) : null));
    if (!userRow && partnerId && user.database) {
      try {
        const tenantRows = await this.tenantDatabaseService.query<any>(
          user.database,
          'SELECT email, user_id FROM public.user WHERE partner_id = $1 LIMIT 1',
          [partnerId],
        );
        if (tenantRows.length > 0 && tenantRows[0]?.email) {
          const rows = await this.authDatabaseService.query<any>(
            'SELECT user_id, email, password, name FROM public."user" WHERE lower(email) = lower($1) AND group_id = $2 LIMIT 1',
            [tenantRows[0].email.trim().toLowerCase(), user.groupId],
          );
          if (rows.length > 0) {
            userRow = rows[0];
          }
        }
      } catch (err) {
        this.logger.warn(`Error buscando partner ${partnerId} en tenant ${user.database}: ${err}`);
      }
    }

    if (!userRow) {
      throw new NotFoundException('Usuario no encontrado para enviar la invitación');
    }

    const passwordToSend =
      userRow.password?.trim() || defaultPassword(userRow.name || 'usuario');

    let verifyToken: string | undefined;
    try {
      verifyToken = await this.jwtService.signAsync(
        {
          sub: userRow.user_id,
          userId: userRow.user_id,
          email: userRow.email,
          database: user.database,
          purpose: 'verify-email',
          type: 'email-verification',
        },
        { expiresIn: '7d' },
      );
    } catch (err) {
      this.logger.warn(`No se pudo firmar token de verificación: ${err}`);
    }

    await this.emailService.sendUserCredentialsEmail({
      to: userRow.email.trim().toLowerCase(),
      name: userRow.name?.trim() || userRow.email,
      password: passwordToSend,
      database: user.database,
      verifyToken,
    });

    this.logger.log(`Invitación reenviada con éxito a ${userRow.email}`);

    return {
      success: true,
      message: `Correo de invitación reenviado con éxito a ${userRow.email}`,
    };
  }

  async verifyPassword(userId: number, password: string, user: JwtPayload) {
    if (!password) {
      throw new BadRequestException('La contraseña es requerida');
    }
    const targetUserId = userId || user.userId;
    const rows = await this.authDatabaseService.query<{ user_id: number; password: string }>(
      'SELECT user_id, password FROM public."user" WHERE user_id = $1 LIMIT 1',
      [targetUserId],
    );
    if (!rows || rows.length === 0) {
      throw new NotFoundException('Usuario no encontrado');
    }
    if (rows[0].password !== password) {
      throw new BadRequestException('Contraseña actual incorrecta');
    }
    return { success: true, message: 'Contraseña correcta' };
  }

  async updatePassword(userId: number, password: string, user: JwtPayload) {
    if (!password || password.trim() === '') {
      throw new BadRequestException('La contraseña es requerida');
    }
    const targetUserId = userId || user?.userId;
    if (!targetUserId) {
      throw new BadRequestException('Identificador de usuario inválido');
    }
    const res = await this.authDatabaseService.query<{ oj_info: any }>(
      'SELECT * FROM public.fnc_user_password_update($1, $2)',
      [targetUserId, password],
    );
    const info = res[0]?.oj_info;
    if (info?.code && info.code >= 400) {
      throw new BadRequestException(info.message || 'Error al actualizar la contraseña');
    }
    return { success: true, message: 'Contraseña actualizada con éxito' };
  }
}
