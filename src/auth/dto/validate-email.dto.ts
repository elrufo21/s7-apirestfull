import { IsEmail } from 'class-validator';

export class ValidateEmailDto {
  // Email que se valida contra la base central de autenticacion.
  @IsEmail()
  it_email!: string;
}
