import { ValidationPipe } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { json, urlencoded } from 'express';
import { AppModule } from './app.module';

async function bootstrap(): Promise<void> {
  const app = await NestFactory.create(AppModule, { bodyParser: false });

  // Lee origenes permitidos desde env; localhost siempre queda habilitado para desarrollo.
  const corsOrigins = (process.env.CORS_ORIGIN ?? process.env.API_CORS_ORIGIN)
    ?.split(',')
    .map((origin) => origin.trim());

  // Habilita CORS antes de los pipes para que Vite/produccion puedan llamar la API.
  app.enableCors({
    origin: (origin, callback) => {
      const isLocalhost = !origin || /^https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(origin);
      const isAllowedOrigin = !corsOrigins?.length || corsOrigins.includes(origin);

      callback(null, isLocalhost || isAllowedOrigin);
    },
    credentials: true,
  });

  // Permite payloads SUNAT con certificado base64.
  const jsonLimit = process.env.API_JSON_LIMIT ?? '10mb';
  app.use(json({ limit: jsonLimit }));
  app.use(urlencoded({ extended: true, limit: jsonLimit }));

  // Mantiene todos los endpoints bajo /api.
  app.setGlobalPrefix('api');

  // Valida y limpia DTOs recibidos desde el frontend.
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
    }),
  );

  await app.listen(process.env.PORT ?? 3000);
}

void bootstrap();
