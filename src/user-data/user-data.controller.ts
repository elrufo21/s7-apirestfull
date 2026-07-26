import { Controller, Get, Req, UseGuards } from '@nestjs/common';

import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import type { AuthenticatedRequest } from '../auth/jwt-auth.guard';

import { UserDataService } from './user-data.service';

@Controller('user-data')
@UseGuards(JwtAuthGuard)
export class UserDataController {
  constructor(private readonly userDataService: UserDataService) {}

  @Get()
  getUserData(@Req() request: AuthenticatedRequest) {
    return this.userDataService.findByUser(
      request.user.database,
      request.user.userId,
    );
  }
}
