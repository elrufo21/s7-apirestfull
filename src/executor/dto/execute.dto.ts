import {
  IsArray,
  IsInt,
  IsNotEmpty,
  IsOptional,
  IsString,
} from 'class-validator';

export class ExecuteDto {
  @IsString()
  @IsNotEmpty()
  functionName!: string;

  // Compatibilidad con el frontend anterior
  @IsOptional()
  @IsInt()
  userId?: number;

  // Compatibilidad con el frontend anterior
  @IsOptional()
  @IsInt()
  groupId?: number;

  @IsOptional()
  @IsArray()
  companies?: unknown[];

  // Puede venir vacío para funciones que no usan acción
  @IsOptional()
  @IsString()
  action?: string;

  @IsOptional()
  data?: unknown;
}
