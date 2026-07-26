import {
  Injectable,
  InternalServerErrorException,
  UnauthorizedException,
} from '@nestjs/common';
import { AuthDatabaseService } from '../auth-database/auth-database.service';
import { LoginDto } from './dto/login.dto';
import { LoginProcedureResult, LoginUser } from './auth.types';
import { JwtService } from '@nestjs/jwt';
import { ValidateEmailDto } from './dto/validate-email.dto';
@Injectable()
export class AuthService {
  constructor(
    private readonly authDatabaseService: AuthDatabaseService,
    private readonly jwtService: JwtService,
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
    // Usa la base central de auth porque esta llamada ocurre antes del JWT tenant.
    return this.authDatabaseService.query(
      `
      SELECT *
      FROM public.fnc_user_validate_email($1)
      `,
      [dto.it_email],
    );
  }
}
