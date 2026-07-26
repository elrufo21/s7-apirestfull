import { Body, Controller, Post } from '@nestjs/common';
import { AuthService } from './auth.service';
import { LoginDto } from './dto/login.dto';
import { ValidateEmailDto } from './dto/validate-email.dto';

@Controller('auth')
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  @Post('login')
  login(@Body() dto: LoginDto) {
    return this.authService.login(dto);
  }

  @Post('validate-email')
  validateEmail(@Body() dto: ValidateEmailDto) {
    // Valida email sin JWT porque se usa antes de recuperar contraseña.
    return this.authService.validateEmail(dto);
  }
}
