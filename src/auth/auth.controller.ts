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

  @Post('password/reset-email')
  sendPasswordResetEmail(@Body() body: any) {
    return this.authService.sendPasswordResetEmail(body);
  }

  @Post('reset-password')
  resetPassword(@Body() dto: { userId: number | string; token: string; password: string }) {
    return this.authService.resetPassword(dto);
  }

  @Post('verify-email')
  verifyEmail(@Body() dto: { token: string }) {
    return this.authService.verifyEmail(dto?.token);
  }
}
