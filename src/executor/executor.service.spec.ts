import { getDefaultProductImage } from './executor.service';

describe('getDefaultProductImage', () => {
  it('keeps legacy behavior when no default flag exists', () => {
    expect(
      getDefaultProductImage([{ path: 'first' }, { path: 'second' }]),
    ).toEqual({
      path: 'first',
    });
  });

  it('returns no product image when every related image is unselected', () => {
    expect(
      getDefaultProductImage([
        { path: 'first', isDefault: false },
        { path: 'second', isDefault: false },
      ]),
    ).toBeNull();
  });

  it('returns the explicitly selected image', () => {
    expect(
      getDefaultProductImage([
        { path: 'first', isDefault: false },
        { path: 'second', isDefault: true },
      ]),
    ).toEqual({ path: 'second', isDefault: true });
  });
});
