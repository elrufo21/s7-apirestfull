import { Type } from 'class-transformer';
import {
  IsEmail,
  IsInt,
  IsNotEmpty,
  IsOptional,
  IsString,
} from 'class-validator';

export class CreateUserDto {
  // Se acepta por compatibilidad; el grupo real siempre sale del JWT.
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  group_id?: number;

  @IsString()
  @IsNotEmpty()
  state!: string;

  @IsString()
  @IsNotEmpty()
  name!: string;

  @IsEmail()
  email!: string;
}
