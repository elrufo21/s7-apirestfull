import { Body, Controller, Post, Req, UseGuards } from '@nestjs/common';

import { ExecutorService } from './executor.service';
import { ExecuteDto } from './dto/execute.dto';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import type { AuthenticatedRequest } from '../auth/jwt-auth.guard';

@Controller('executor')
@UseGuards(JwtAuthGuard)
export class ExecutorController {
  constructor(private readonly executorService: ExecutorService) {}

  @Post()
  execute(@Body() dto: ExecuteDto, @Req() request: AuthenticatedRequest) {
    return this.executorService.execute(dto, request.user);
  }
}
