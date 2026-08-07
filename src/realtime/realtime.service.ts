import { Injectable, Logger } from '@nestjs/common';
import type { Server as HttpServer } from 'node:http';
import { WebSocketServer, WebSocket } from 'ws';

type RealtimeEvent = {
  type: string;
  payload?: Record<string, unknown>;
};

@Injectable()
export class RealtimeService {
  private readonly logger = new Logger(RealtimeService.name);
  private server?: WebSocketServer;

  bind(httpServer: HttpServer) {
    if (this.server) return;

    this.server = new WebSocketServer({ server: httpServer, path: '/realtime' });

    this.server.on('connection', (socket, request) => {
      if (!this.isAllowedOrigin(request.headers.origin)) {
        socket.close(1008, 'Origin not allowed');
        return;
      }

      socket.send(JSON.stringify({ type: 'connected' }));
    });

    this.logger.log('Realtime WebSocket activo en /realtime');
  }

  broadcast(event: RealtimeEvent) {
    if (!this.server) return;

    const message = JSON.stringify(event);

    for (const client of this.server.clients) {
      if (client.readyState === WebSocket.OPEN) {
        client.send(message);
      }
    }
  }

  private isAllowedOrigin(origin?: string) {
    const corsOrigins = (process.env.CORS_ORIGIN ?? process.env.API_CORS_ORIGIN)
      ?.split(',')
      .map((value) => value.trim());
    const isLocalhost = !origin || /^https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(origin);

    return isLocalhost || !corsOrigins?.length || corsOrigins.includes(origin);
  }
}
