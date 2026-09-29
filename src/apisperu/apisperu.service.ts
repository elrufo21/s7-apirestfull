import { Injectable, Logger } from '@nestjs/common';
import axios from 'axios';
import AdmZip from 'adm-zip';
import fs from 'fs';
import path from 'path';
import { unzipCDR } from '../sunat/legacy/unzip.legacy';
import {
  uploadFileFromDisk,
  uploadTwoZipsFromDisk,
  r2Prefixes,
} from '../sunat/legacy/r2-storage.legacy';
import { saveTempZip } from '../sunat/legacy/to-drive-temp.legacy';

function numeroALetras(num: number, moneda = 'SOLES'): string {
  const unidades = ['CERO', 'UNO', 'DOS', 'TRES', 'CUATRO', 'CINCO', 'SEIS', 'SIETE', 'OCHO', 'NUEVE'];
  const decenas = ['DIEZ', 'ONCE', 'DOCE', 'TRECE', 'CATORCE', 'QUINCE', 'DIECISÉIS', 'DIECISIETE', 'DIECIOCHO', 'DIECINUEVE'];
  const decenas2 = ['VEINTE', 'TREINTA', 'CUARENTA', 'CINCUENTA', 'SESENTA', 'SETENTA', 'OCHENTA', 'NOVENTA'];
  const centenas = ['CIEN', 'DOSCIENTOS', 'TRESCIENTOS', 'CUATROCIENTOS', 'QUINIENTOS', 'SEISCIENTOS', 'SETECIENTOS', 'OCHOCIENTOS', 'NOVECIENTOS'];

  function convertir(n: number): string {
    if (n < 10) return unidades[n];
    if (n < 20) return decenas[n - 10];
    if (n < 100) {
      const dec = Math.floor(n / 10);
      const uni = n % 10;
      return decenas2[dec - 2] + (uni ? ' Y ' + unidades[uni] : '');
    }
    if (n < 1000) {
      const cen = Math.floor(n / 100);
      const resto = n % 100;
      const centena = cen === 1 && resto > 0 ? 'CIENTO' : centenas[cen - 1];
      return centena + (resto ? ' ' + convertir(resto) : '');
    }
    if (n < 1000000) {
      const mil = Math.floor(n / 1000);
      const resto = n % 1000;
      const miles = mil === 1 ? 'MIL' : convertir(mil) + ' MIL';
      return miles + (resto ? ' ' + convertir(resto) : '');
    }
    return '***';
  }

  const cleanNum = Math.max(0, Number(num) || 0);
  const [entero, decimal] = cleanNum.toFixed(2).split('.');
  const intVal = parseInt(entero, 10);
  const letras = intVal === 0 ? 'CERO' : convertir(intVal);
  return `SON ${letras} CON ${decimal}/100 ${moneda.toUpperCase()}`;
}

@Injectable()
export class ApisPeruService {
  private readonly logger = new Logger(ApisPeruService.name);
  private readonly apisPeruBaseUrl =
    process.env.APIPERU_BASE_URL || 'https://facturacion.apisperu.com/api/v1';

  /**
   * Obtiene el token de autenticación para APIs Perú
   */
  private getToken(customToken?: string): string {
    const token =
      customToken ||
      process.env.APIPERU_TOKEN ||
      process.env.APISPERU_TOKEN ||
      '';
    if (!token) {
      this.logger.warn(
        'No se ha configurado APIPERU_TOKEN en las variables de entorno.',
      );
    }
    return token.trim();
  }

  /**
   * Construye el JSON oficial que APIs Perú espera recibir según su especificación OpenAPI 3.0 / UBL 2.1
   */
  buildInvoicePayload(rawInput: any, isBoleta: boolean): any {
    // Si ya viene directamente formateado para APIs Perú con ublVersion y company/client estructurado
    if (rawInput?.ublVersion && rawInput?.details && Array.isArray(rawInput?.details)) {
      return rawInput;
    }

    // Normalizar si viene envuelto en overrides o directo
    const cabecera = rawInput?.overrides?.cabecera || {};
    const emisor = rawInput?.overrides?.emisor || rawInput?.emisor || {};
    const cliente = rawInput?.overrides?.cliente || rawInput?.cliente || {};
    const rawLines =
      rawInput?.move_lines ||
      rawInput?.overrides?.items ||
      rawInput?.items ||
      rawInput?.details ||
      [];

    // 1. Serie y Correlativo
    const docName =
      rawInput?.name ||
      rawInput?.document_number ||
      cabecera?.id ||
      '';
    const rawName = String(docName || '').trim();
    const rawDocNumber = String(rawInput?.document_number || '').trim();
    const match = rawName.match(/^([FB]\w{3})(?:[\/\s-](?:\d{4}[\/\s-])?)?(\d+)$/i);
    const prefix = isBoleta ? 'B' : 'F';
    let serie = match ? `${match[1].toUpperCase()}` : `${prefix}001`;
    if (isBoleta && serie.startsWith('F')) {
      serie = `B${serie.slice(1)}`;
    } else if (!isBoleta && serie.startsWith('B')) {
      serie = `F${serie.slice(1)}`;
    }
    const correlativoRaw = match
      ? match[2]
      : rawDocNumber || String(rawInput?.move_id || '1');
    const correlativo = String(parseInt(correlativoRaw, 10) || 1);

    // 2. Fechas
    const rawDate =
      rawInput?.date ||
      rawInput?.invoice_date ||
      cabecera?.issueDate ||
      new Date().toISOString();
    const rawDueDate =
      rawInput?.date_due ||
      rawInput?.invoice_date_due ||
      cabecera?.dueDate ||
      rawDate;

    const toIsoWithOffset = (d: string) => {
      const dt = new Date(d);
      if (isNaN(dt.getTime())) {
        return new Date().toISOString().replace(/\.\d{3}Z$/, '-05:00');
      }
      return dt.toISOString().replace(/\.\d{3}Z$/, '-05:00');
    };

    const fechaEmision = toIsoWithOffset(rawDate);
    const fecVencimiento = toIsoWithOffset(rawDueDate);

    // 3. Moneda y Operación
    const tipoMoneda =
      rawInput?.currency_name ||
      cabecera?.documentCurrencyCode ||
      'PEN';
    const tipoOperacion =
      rawInput?.operation_type ||
      cabecera?.profileId ||
      '0101';

    // 4. Datos del Emisor
    const emisorRuc =
      String(emisor?.ruc || process.env.SUNAT_TEST_RUC || '20603390033').trim();
    const emisorRazonSocial =
      emisor?.razonSocial || 'DESTINO AVENTURA PERÚ EMPRESA INDIVIDUAL DE RESPONSABILIDAD LIMITADA';
    const emisorNombreComercial =
      emisor?.nombreComercial || 'DESTINO AVENTURA PERÚ';
    const emisorAddress = emisor?.address || {};

    // 5. Datos del Cliente
    const rawDocType = String(
      cliente?.documentTypeCode ||
      cliente?.tipoDoc ||
      (isBoleta ? '1' : '6'),
    ).trim();
    const rawNumDoc = String(
      cliente?.ruc ||
      cliente?.numDoc ||
      cliente?.identification_number ||
      (isBoleta ? '00000000' : '20000000002'),
    ).trim();
    const clientRazonSocial =
      cliente?.razonSocial ||
      cliente?.nombreComercial ||
      rawInput?.partner_name ||
      (isBoleta ? 'CLIENTES VARIOS' : 'CLIENTE DESTINO S.A.C.');
    const clientAddress = cliente?.address || {};

    // 6. Mapeo de Líneas de Detalle
    let sumGravadas = 0;
    let sumExoneradas = 0;
    let sumInafectas = 0;
    let sumIgv = 0;

    const details = (Array.isArray(rawLines) ? rawLines : [])
      .filter((l: any) => l.type === 'L' || !l.type)
      .map((line: any, idx: number) => {
        const qty = Math.max(0.0001, Number(line.quantity || line.cantidad || 1));
        const priceUnit = Number(line.price_unit || line.mtoValorUnitario || 0);
        const valorVenta = Number(
          line.amount_untaxed_total ??
          line.amount_untaxed ??
          line.mtoValorVenta ??
          (priceUnit * qty),
        );
        const igv = Number(
          line.amount_tax_total ??
          line.amount_tax ??
          line.igv ??
          0,
        );

        // Identificar porcentaje de IGV y tipo de afectación
        const taxPercent = Number(
          line.move_lines_taxes?.[0]?.percentage ??
          line.porcentajeIgv ??
          (igv > 0 ? 18 : 0),
        );

        const tipAfeIgv = String(
          line.tipAfeIgv ||
          (taxPercent > 0 ? '10' : '20'),
        );

        if (tipAfeIgv === '10') {
          sumGravadas += valorVenta;
          sumIgv += igv;
        } else if (tipAfeIgv === '20') {
          sumExoneradas += valorVenta;
        } else {
          sumInafectas += valorVenta;
        }

        const totalImpuestos = igv;
        const totalItem = valorVenta + igv;
        const mtoPrecioUnitario = Number((totalItem / qty).toFixed(2));

        return {
          codProducto: String(line.product_id || line.codProducto || `ITEM-${idx + 1}`),
          unidad: line.uom_name === 'Unidades' ? 'NIU' : (line.uom_name || line.unitCode || 'NIU'),
          descripcion: line.name || line.description || line.descripcion || 'PRODUCTO/SERVICIO',
          cantidad: Number(qty.toFixed(4)),
          mtoValorUnitario: Number(priceUnit.toFixed(2)),
          mtoValorVenta: Number(valorVenta.toFixed(2)),
          mtoBaseIgv: Number(valorVenta.toFixed(2)),
          porcentajeIgv: taxPercent,
          igv: Number(igv.toFixed(2)),
          tipAfeIgv,
          totalImpuestos: Number(totalImpuestos.toFixed(2)),
          mtoPrecioUnitario,
        };
      });

    // 7. Totales
    const mtoOperGravadas = Number(
      (rawInput?.amount_untaxed ?? sumGravadas).toFixed(2),
    );
    const mtoIGV = Number(
      (rawInput?.amount_tax ?? sumIgv).toFixed(2),
    );
    const totalImpuestos = mtoIGV;
    const valorVenta = Number(
      (mtoOperGravadas + sumExoneradas + sumInafectas).toFixed(2),
    );
    const mtoImpVenta = Number(
      (rawInput?.amount_withtaxed ?? (valorVenta + totalImpuestos)).toFixed(2),
    );

    // 8. Forma de Pago
    const rawPaymentType = String(
      rawInput?.payment_term ||
      rawInput?.payment_type ||
      rawInput?.formaPago?.tipo ||
      'Contado',
    ).toLowerCase();
    const isCredito = rawPaymentType.includes('credito') || rawPaymentType.includes('credit');

    const formaPago: Record<string, any> = {
      moneda: tipoMoneda,
      tipo: isCredito ? 'Credito' : 'Contado',
    };
    if (isCredito) {
      formaPago.monto = mtoImpVenta;
    }

    // 9. Leyenda (monto en letras)
    const monedaNombre = tipoMoneda === 'USD' ? 'DOLARES AMERICANOS' : 'SOLES';
    const legends = [
      {
        code: '1000',
        value: numeroALetras(mtoImpVenta, monedaNombre),
      },
    ];

    return {
      ublVersion: '2.1',
      tipoOperacion,
      tipoDoc: isBoleta ? '03' : '01',
      serie,
      correlativo,
      fechaEmision,
      fecVencimiento,
      formaPago,
      ...(isCredito && Array.isArray(rawInput?.cuotas) && rawInput.cuotas.length > 0
        ? { cuotas: rawInput.cuotas }
        : {}),
      tipoMoneda,
      company: {
        ruc: emisorRuc,
        razonSocial: emisorRazonSocial,
        nombreComercial: emisorNombreComercial,
        address: {
          direccion: emisorAddress?.line || emisorAddress?.direccion || 'CALLE CENTRAL 123',
          provincia: emisorAddress?.cityName || emisorAddress?.provincia || 'LIMA',
          departamento: emisorAddress?.countrySubentity || emisorAddress?.departamento || 'LIMA',
          distrito: emisorAddress?.district || 'LIMA',
          ubigueo: emisorAddress?.ubigeo || emisorAddress?.ubigueo || '150101',
        },
      },
      client: {
        tipoDoc: rawDocType,
        numDoc: rawNumDoc,
        rznSocial: clientRazonSocial,
        address: {
          direccion: clientAddress?.line || clientAddress?.direccion || 'LIMA',
          provincia: clientAddress?.provincia || 'LIMA',
          departamento: clientAddress?.departamento || 'LIMA',
          distrito: clientAddress?.distrito || 'LIMA',
          ubigueo: clientAddress?.ubigueo || clientAddress?.ubigeo || '150101',
        },
      },
      mtoOperGravadas,
      mtoOperExoneradas: Number(sumExoneradas.toFixed(2)),
      mtoOperInafectas: Number(sumInafectas.toFixed(2)),
      mtoIGV,
      totalImpuestos,
      valorVenta,
      subTotal: mtoImpVenta,
      mtoImpVenta,
      details,
      legends,
    };
  }

  /**
   * Envía la factura/boleta al servicio de APIs Perú y formatea la respuesta
   * para cumplir con el contrato esperado por persistEdiResult en el ERP.
   */
  async processInvoice(rawInput: any, isBoleta: boolean, customToken?: string) {
    const token = this.getToken(customToken);
    if (!token) {
      throw new Error(
        'Token de APIs Perú no configurado. Defina APIPERU_TOKEN en el entorno.',
      );
    }

    const payload = this.buildInvoicePayload(rawInput, isBoleta);
    const nombre = `${payload.company.ruc}-${payload.tipoDoc}-${payload.serie}-${payload.correlativo}`;

    this.logger.log(
      `[ApisPeru] Enviando comprobante ${nombre} a ${this.apisPeruBaseUrl}/invoice/send...`,
    );

    let apiResponse: any;
    try {
      apiResponse = await axios.post(
        `${this.apisPeruBaseUrl}/invoice/send`,
        payload,
        {
          headers: {
            Authorization: `Bearer ${token}`,
            'Content-Type': 'application/json',
            Accept: 'application/json',
          },
          timeout: 45000,
        },
      );
    } catch (httpError: any) {
      this.logger.error(
        `[ApisPeru] Error HTTP al emitir ${nombre}:`,
        httpError?.response?.data || httpError?.message,
      );

      const errData = httpError?.response?.data;
      const status = httpError?.response?.status || 500;
      const errorMsg =
        (Array.isArray(errData)
          ? errData.map((e: any) => `${e.property}: ${e.message}`).join(', ')
          : errData?.message || errData?.error) || httpError?.message || 'Error de comunicación con APIs Perú';

      const errObj: any = new Error(errorMsg);
      errObj.statusCode = status;
      errObj.sunatCode = errData?.code || '9999';
      errObj.details = errData;
      throw errObj;
    }

    const data = apiResponse?.data;
    const xmlBase64 = data?.xml || '';
    const hash = data?.hash || '';
    const sunatResponse = data?.sunatResponse || {};
    const cdrBase64 = sunatResponse?.cdrZip || '';
    const cdrResponse = sunatResponse?.cdrResponse || {};
    const isSuccess = Boolean(sunatResponse?.success && (cdrResponse?.code === '0' || cdrResponse?.code === 0));

    // Descomprimir CDR para extraer el XML de respuesta oficial
    let cdrParsed: any = null;
    if (cdrBase64) {
      try {
        cdrParsed = unzipCDR(
          cdrBase64,
          payload.company.ruc,
          payload.serie,
          payload.correlativo,
        );
      } catch (unzipErr) {
        this.logger.warn(`[ApisPeru] No se pudo parsear XML del CDR: ${unzipErr}`);
      }
    }

    // Guardar temporalmente los archivos para auditoría R2
    let uploadResult: any = undefined;
    let requestTempPath: string | undefined;
    let responseTempPath: string | undefined;

    try {
      if (xmlBase64) {
        const xmlBuffer = Buffer.from(xmlBase64, 'base64');
        const zipReq = new AdmZip();
        zipReq.addFile(`${nombre}.xml`, xmlBuffer);
        requestTempPath = saveTempZip(zipReq.toBuffer(), `request-${nombre}.zip`);
      }

      if (cdrBase64) {
        const cdrBuffer = Buffer.from(cdrBase64, 'base64');
        responseTempPath = saveTempZip(cdrBuffer, `response-${nombre}.zip`);
      }

      if (requestTempPath && responseTempPath) {
        const storageUpload = await uploadTwoZipsFromDisk({
          requestPath: requestTempPath,
          requestName: `request-${nombre}.zip`,
          responsePath: responseTempPath,
          responseName: `response-${nombre}.zip`,
        });

        uploadResult = {
          success: true,
          ...storageUpload,
          requestTempPath,
          responseTempPath,
        };
      }
    } catch (storageErr: any) {
      this.logger.warn(
        `[ApisPeru] Advertencia guardando en Cloudflare R2: ${storageErr?.message || storageErr}`,
      );
      uploadResult = {
        success: false,
        message: storageErr?.message || 'Error subiendo a R2',
        requestTempPath,
        responseTempPath,
      };
    }

    const xmlRequestContent = xmlBase64 ? Buffer.from(xmlBase64, 'base64').toString('utf8') : '';
    const codeSunat = String(cdrResponse?.code ?? cdrParsed?.responseCode ?? (isSuccess ? '0' : '9999'));
    const descriptionSunat = String(cdrResponse?.description ?? cdrParsed?.description ?? (isSuccess ? 'Comprobante aceptado por SUNAT' : 'Rechazado'));

    return {
      success: isSuccess,
      flow: 'apisperu_builder',
      nombre,
      hash,
      xml: xmlRequestContent,
      zip: xmlBase64,
      cdrBase64,
      cdr: cdrParsed,
      uploadResult,
      toDb: {
        xml_request: xmlRequestContent,
        xml_response: cdrParsed?.xmlContent || '',
        code_sunat: codeSunat,
        description_sunat: descriptionSunat,
        date: cdrParsed?.date || new Date().toISOString(),
      },
    };
  }

  /**
   * Genera el PDF oficial a través del endpoint /invoice/pdf de APIs Perú
   */
  async getInvoicePdf(rawInput: any, isBoleta: boolean, customToken?: string): Promise<Buffer> {
    const token = this.getToken(customToken);
    const payload = this.buildInvoicePayload(rawInput, isBoleta);

    const response = await axios.post(
      `${this.apisPeruBaseUrl}/invoice/pdf`,
      payload,
      {
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/json',
          Accept: 'application/pdf',
        },
        responseType: 'arraybuffer',
        timeout: 30000,
      },
    );

    return Buffer.from(response.data);
  }

  /**
   * Consulta el estado del comprobante ante SUNAT vía APIs Perú
   */
  async getInvoiceStatus(params: { tipo: string; serie: string; numero: string; ruc?: string; customToken?: string }) {
    const token = this.getToken(params.customToken);
    const response = await axios.get(
      `${this.apisPeruBaseUrl}/invoice/status`,
      {
        params: {
          tipo: params.tipo,
          serie: params.serie,
          numero: params.numero,
          ...(params.ruc ? { ruc: params.ruc } : {}),
        },
        headers: {
          Authorization: `Bearer ${token}`,
          Accept: 'application/json',
        },
        timeout: 30000,
      },
    );
    return response.data;
  }
}
