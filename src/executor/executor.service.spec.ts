import { getDefaultProductImage, getPaymentInvoiceLinkInput } from './executor.service';

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

describe('getPaymentInvoiceLinkInput', () => {
  it('links only a successfully created invoice payment', () => {
    expect(
      getPaymentInvoiceLinkInput(
        { move_id: 209, amount: 10 },
        [{ oj_data: { payment_id: 80 } }],
      ),
    ).toEqual({ paymentId: 80, moveId: 209, amount: 10 });
  });
});
