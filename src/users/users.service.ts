import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';

import { AuthDatabaseService } from '../auth-database/auth-database.service';
import type { JwtPayload } from '../auth/jwt-auth.guard';
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
  constructor(private readonly authDatabaseService: AuthDatabaseService) {}

  async create(dto: CreateUserDto, user: JwtPayload) {
    const created = await this.authDatabaseService.query<{ created: boolean }>(
      'SELECT public.fnc_create_user($1, $2, $3, $4, $5) AS created',
      [
        user.groupId,
        dto.state.trim(),
        dto.name.trim(),
        dto.email.trim().toLowerCase(),
        defaultPassword(dto.name),
      ],
    );

    if (!created[0]?.created) {
      throw new BadRequestException('No se pudo crear el usuario');
    }

    const userRow = await this.authDatabaseService.query<{ user_id: number }>(
      'SELECT user_id FROM public."user" WHERE lower(email) = lower($1) AND group_id = $2 LIMIT 1',
      [dto.email.trim().toLowerCase(), user.groupId],
    );

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
}
