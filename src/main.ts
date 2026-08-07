import { ValidationPipe } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { json, urlencoded } from 'express';
import { join } from 'path';
import { NestExpressApplication } from '@nestjs/platform-express';
import { AppModule } from './app.module';
import { RealtimeService } from './realtime/realtime.service';

async function bootstrap(): Promise<void> {
  const app = await NestFactory.create<NestExpressApplication>(AppModule, {
    bodyParser: false,
  });

  // Publica los archivos guardados en /app/storage
  app.useStaticAssets(join(process.cwd(), 'storage'), {
    prefix: '/storage/',
  });

  // Lee orígenes permitidos desde env.
  const corsOrigins = (process.env.CORS_ORIGIN ?? process.env.API_CORS_ORIGIN)
    ?.split(',')
    .map((origin) => origin.trim());

  app.enableCors({
    origin: (origin, callback) => {
      const isLocalhost =
        !origin || /^https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(origin);

      const isAllowedOrigin =
        !origin || !corsOrigins?.length || corsOrigins.includes(origin);

      callback(null, isLocalhost || isAllowedOrigin);
    },
    credentials: true,
  });

  const jsonLimit = process.env.API_JSON_LIMIT ?? '10mb';

  app.use(json({ limit: jsonLimit }));
  app.use(urlencoded({ extended: true, limit: jsonLimit }));

  app.setGlobalPrefix('api');

  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
    }),
  );

  app.get(RealtimeService).bind(app.getHttpServer());

  await app.listen(process.env.PORT ?? 3000);
}

void bootstrap();
