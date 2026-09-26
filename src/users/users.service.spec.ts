import { BadRequestException, NotFoundException } from '@nestjs/common';

import { UsersService } from './users.service';

describe('UsersService', () => {
  const authDatabaseService = { query: jest.fn() };
  const service = new UsersService(authDatabaseService as any);
  const user = { userId: 10, groupId: 7, sub: 10, database: 'tenant' };

  beforeEach(() => jest.resetAllMocks());

  it('uses the authenticated group and preserves the legacy default password', async () => {
    authDatabaseService.query.mockResolvedValue([{ created: true }]);

    await expect(
      service.create(
        {
          group_id: 99,
          state: 'A',
          name: 'José Pérez',
          email: ' USER@EXAMPLE.COM ',
        },
        user,
      ),
    ).resolves.toEqual({
      success: true,
      message: 'Usuario creado correctamente',
    });

    expect(authDatabaseService.query).toHaveBeenCalledWith(expect.any(String), [
      7,
      'A',
      'José Pérez',
      'user@example.com',
      'joseperez',
    ]);
  });

  it('does not update users outside the authenticated group', async () => {
    authDatabaseService.query.mockResolvedValue([{ exists: false }]);

    await expect(
      service.update(
        99,
        { state: 'A', name: 'Otra', email: 'otra@example.com' },
        user,
      ),
    ).rejects.toBeInstanceOf(NotFoundException);
  });

  it('reports a failed creation', async () => {
    authDatabaseService.query.mockResolvedValue([{ created: false }]);

    await expect(
      service.create(
        { state: 'A', name: 'Otra', email: 'otra@example.com' },
        user,
      ),
    ).rejects.toBeInstanceOf(BadRequestException);
  });
});
