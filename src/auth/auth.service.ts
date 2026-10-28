import {
  BadRequestException,
  Injectable,
  Logger,
  InternalServerErrorException,
  NotFoundException,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { AuthDatabaseService } from '../auth-database/auth-database.service';
import { TenantDatabaseService } from '../tenant-database/tenant-database.service';
import { EmailService } from '../email/email.service';
import { LoginDto } from './dto/login.dto';
import { LoginProcedureResult, LoginUser } from './auth.types';
import { JwtService } from '@nestjs/jwt';
import { ValidateEmailDto } from './dto/validate-email.dto';

@Injectable()
export class AuthService {
  private readonly logger = new Logger(AuthService.name);

  constructor(
    private readonly authDatabaseService: AuthDatabaseService,
    private readonly tenantDatabaseService: TenantDatabaseService,
    private readonly emailService: EmailService,
    private readonly jwtService: JwtService,
    private readonly configService: ConfigService,
  ) {}

  async login(dto: LoginDto): Promise<{
    success: true;
    data: LoginProcedureResult;
    user: LoginUser;
    token: string;
  }> {
    const rows = await this.authDatabaseService.query<LoginProcedureResult>(
      `
      SELECT oj_info, oj_data
      FROM public.fnc_user_login($1, $2)
      `,
      [dto.email, dto.password],
    );

    const loginResult = rows[0];

    if (!loginResult) {
      throw new InternalServerErrorException(
        'La función de login no devolvió información',
      );
    }

    const info = loginResult.oj_info;
    const data = loginResult.oj_data;

    if (info.code !== 200) {
      throw new UnauthorizedException(info.message ?? 'Credenciales inválidas');
    }

    const firstUser = Array.isArray(data) ? data[0] : null;

    if (!firstUser?.user_id) {
      throw new InternalServerErrorException(
        'No se pudo obtener el usuario desde la función de login',
      );
    }
    if (!firstUser.database) {
      throw new InternalServerErrorException(
        'El usuario no tiene una base de datos asignada',
      );
    }

    const token = await this.jwtService.signAsync({
      sub: firstUser.user_id,
      userId: firstUser.user_id,
      groupId: firstUser.group_id,
      database: firstUser.database,
    });
    return {
      success: true,
      data: loginResult,
      user: firstUser,
      token,
    };
  }

  async validateEmail(dto: ValidateEmailDto) {
    try {
      const email = dto?.it_email?.trim().toLowerCase();
      if (!email) {
        return [
          {
            oj_info: { code: 401, type: 'error', action: 'select', message: '¡El correo es requerido!' },
            oj_data: null,
          },
        ];
      }

      const rows = await this.authDatabaseService.query<{ user_id: number; email: string; name: string }>(
        'SELECT user_id, email, name FROM public."user" WHERE lower(email) = lower($1) LIMIT 1',
        [email],
      );

      if (!rows || rows.length === 0) {
        return [
          {
            oj_info: { code: 401, type: 'error', action: 'select', message: '¡El correo no existe!' },
            oj_data: null,
          },
        ];
      }

      return [
        {
          oj_info: { code: 201, type: 'success', action: 'select', message: '¡Se realizó la consulta con éxito!' },
          oj_data: { user_id: rows[0].user_id, email: rows[0].email, name: rows[0].name },
        },
      ];
    } catch (error: any) {
      this.logger.error(`Error en validateEmail: ${error?.message || error}`);
      return [
        {
          oj_info: { code: 401, type: 'error', action: 'select', message: 'No se pudo consultar el correo' },
          oj_data: null,
        },
      ];
    }
  }

  async sendPasswordResetEmail(body: { email?: string; userId?: number | string; name?: string; resetUrl?: string }) {
    const email = (body.email || (body as any).to)?.trim().toLowerCase();
    if (!email) {
      throw new BadRequestException('El correo electrónico es requerido');
    }

    let userId = body.userId;
    let name = body.name;

    if (!userId) {
      const userRows = await this.authDatabaseService.query<{ user_id: number; name: string }>(
        'SELECT user_id, name FROM public."user" WHERE lower(email) = lower($1) LIMIT 1',
        [email],
      );
      if (userRows.length > 0) {
        userId = userRows[0].user_id;
        name = name || userRows[0].name;
      }
    }

    if (!userId) {
      throw new NotFoundException('No se encontró ningún usuario con ese correo electrónico');
    }

    const frontendUrl =
      this.configService.get<string>('FRONTEND_URL') ||
      (this.configService.get<string>('CORS_ORIGIN') || '').split(',')[0] ||
      'http://localhost:5173';

    const resetToken = await this.jwtService.signAsync(
      { sub: userId, userId, email, purpose: 'reset-password', type: 'password-reset' },
      { expiresIn: '1h' },
    );

    const resetUrl = `${frontendUrl}/reset-password/${userId}/${resetToken}`;

    return this.emailService.sendPasswordResetEmail({
      to: email,
      name,
      resetUrl,
      userId,
    });
  }

  async resetPassword(dto: { userId: number | string; token: string; password: string }) {
    const { userId, token, password } = dto ?? {};
    if (!userId || !token || !password) {
      throw new BadRequestException('userId, token y password son requeridos');
    }

    try {
      const payload = await this.jwtService.verifyAsync(token);
      const isResetPurpose = payload.purpose === 'reset-password' || payload.type === 'password-reset';
      if (!isResetPurpose) {
        throw new BadRequestException('Token de restablecimiento inválido');
      }
      if (String(payload.sub || payload.userId) !== String(userId)) {
        throw new BadRequestException('El token no corresponde al usuario');
      }
    } catch {
      throw new BadRequestException('El enlace de restablecimiento es inválido o ha expirado');
    }

    const res = await this.authDatabaseService.query<{ oj_info: any }>(
      'SELECT * FROM public.fnc_user_password_update($1, $2)',
      [Number(userId), password],
    );

    const info = res[0]?.oj_info;
    if (info?.code && info.code >= 400) {
      throw new BadRequestException(info.message || 'Error al actualizar contraseña');
    }

    return { success: true, message: '¡Contraseña restablecida con éxito!' };
  }

  async verifyEmail(dto: { token: string; password?: string } | string) {
    const token = typeof dto === 'string' ? dto : dto?.token;
    const password = typeof dto === 'string' ? undefined : dto?.password;

    if (!token) {
      throw new BadRequestException('Token de verificación requerido');
    }

    let payload: any;
    try {
      payload = await this.jwtService.verifyAsync(token);
      const isVerifyPurpose = payload.purpose === 'verify-email' || payload.type === 'email-verification';
      if (!isVerifyPurpose) {
        throw new BadRequestException('Token de verificación inválido');
      }
    } catch {
      throw new BadRequestException('El enlace de validación no es válido o ha expirado');
    }

    const targetUserId = payload.userId || payload.sub;
    const targetDb = payload.database || 'railway';

    try {
      // 1. Si el usuario definió una nueva contraseña, actualizarla en s7_auth
      if (password && password.trim() !== '') {
        const passRes = await this.authDatabaseService.query<{ oj_info: any }>(
          'SELECT * FROM public.fnc_user_password_update($1, $2)',
          [Number(targetUserId), password.trim()],
        );
        const info = passRes[0]?.oj_info;
        if (info?.code && info.code >= 400) {
          throw new BadRequestException(info.message || 'Error al guardar la contraseña');
        }
      }

      // 2. Activar usuario en la base central de login (s7_auth)
      await this.authDatabaseService.query(
        'UPDATE public."user" SET state = $1 WHERE user_id = $2',
        ['A', Number(targetUserId)],
      );

      // 3. Activar y marcar verified en la base tenant (railway)
      try {
        await this.tenantDatabaseService.query(
          targetDb,
          'UPDATE public."user" SET verified = true, state = $1 WHERE user_id = $2',
          ['A', Number(targetUserId)],
        );
      } catch (tenantErr) {
        this.logger.warn(`No se pudo actualizar verified en tenant (${targetDb}): ${tenantErr}`);
      }
    } catch (err: any) {
      if (err instanceof BadRequestException) throw err;
      throw new BadRequestException(`No se pudo completar la activación: ${err?.message || err}`);
    }

    return {
      success: true,
      message: '¡Cuenta activada y contraseña configurada con éxito!',
    };
  }
}
