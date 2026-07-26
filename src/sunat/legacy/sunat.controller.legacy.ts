// @ts-nocheck
import { signXML } from "./xml-signer.legacy";
import { makeZip } from "./zip.legacy";
import { sendToSunat } from "./sunat-service.legacy";
import { unzipCDR } from "./unzip.legacy";
import {
  buildBoletaXML,
  buildCreditNoteXML,
  buildDebitNoteXML,
  buildInvoiceXML,
} from "./xml-builder.legacy";
import fs from "fs";
import path from "path";
import {
  deleteObjectFromR2,
  r2Prefixes,
  uploadFileFromDisk,
  uploadCertificateFromDisk,
  uploadTwoZipsFromDisk,
} from "./r2-storage.legacy";
import { saveTempZip } from "./to-drive-temp.legacy";
import {
  AFECTACION_IGV,
  MEDIOS_PAGO,
  MONEDAS,
  TIPO_DOCUMENTO,
  TRIBUTOS,
  UNIDADES,
} from "./sunat-catalogs.legacy";

const SUNAT_TEST_XML_FILE =
  process.env.SUNAT_TEST_XML_FILE || "20100100100-01-F001-175.xml";
const SUNAT_TEST_RUC = process.env.SUNAT_TEST_RUC || "20100100100";
const SUNAT_TEST_TIPO_COMPROBANTE =
  process.env.SUNAT_TEST_TIPO_COMPROBANTE || "01";
const SUNAT_TEST_SERIE = process.env.SUNAT_TEST_SERIE || "F001";
const SUNAT_TEST_CORRELATIVO = process.env.SUNAT_TEST_CORRELATIVO || "175";
const DEFAULT_IDENTITY_DOC_TYPE = "6";

const VALID_CURRENCY_CODES = new Set(
  MONEDAS.map((item) =>
    String(item?.codigo || "")
      .trim()
      .toUpperCase(),
  ).filter(Boolean),
);
const MEDIO_PAGO_BY_FACTPRO = new Map(
  MEDIOS_PAGO.map((item) => [Number(item?.factpro), item]),
);
const TIPO_DOCUMENTO_BY_FACTPRO = new Map(
  TIPO_DOCUMENTO.map((item) => [Number(item?.factpro), item]),
);
const TIPO_DOCUMENTO_BY_SUNAT = new Map(
  TIPO_DOCUMENTO.map((item) => [String(item?.sunat || "").trim(), item]).filter(
    ([key]) => key,
  ),
);
const AFECTACION_BY_FACTPRO = new Map(
  AFECTACION_IGV.map((item) => [Number(item?.factpro), item]),
);
const AFECTACION_BY_SUNAT = new Map(
  AFECTACION_IGV.map((item) => [String(item?.sunat || "").trim(), item]).filter(
    ([key]) => key,
  ),
);
const TRIBUTO_BY_FACTPRO = new Map(
  TRIBUTOS.map((item) => [Number(item?.factpro), item]),
);
const UOM_BY_NAME = new Map(
  UNIDADES.map((item) => [
    normalizeText(item?.nombre),
    String(item?.codigo || "")
      .trim()
      .toUpperCase(),
  ]).filter(([key, code]) => key && code),
);
const TAX_SCHEME_BY_SUNAT = Object.freeze({
  1000: { id: "1000", name: "IGV", taxTypeCode: "VAT" },
  9997: { id: "9997", name: "EXO", taxTypeCode: "VAT" },
  9998: { id: "9998", name: "INA", taxTypeCode: "FRE" },
  2000: { id: "2000", name: "ISC", taxTypeCode: "EXC" },
  7152: { id: "7152", name: "ICBPER", taxTypeCode: "OTH" },
});
const TAX_CATEGORY_BY_AFECTACION = Object.freeze({
  10: "S",
  20: "E",
  21: "E",
  30: "O",
  40: "G",
});

function normalizeText(value) {
  return String(value || "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .trim();
}

function firstNonEmptyString(values = []) {
  for (const value of values) {
    const clean = String(value ?? "").trim();
    if (clean) {
      return clean;
    }
  }
  return "";
}

function resolveCurrencyCode(rawValue, fallback = "PEN") {
  const candidate = String(rawValue || "")
    .trim()
    .toUpperCase();
  if (candidate && VALID_CURRENCY_CODES.has(candidate)) {
    return candidate;
  }
  return fallback;
}

function resolveCustomerDocumentNumber(payload = {}) {
  return firstNonEmptyString([
    payload?.cliente?.ruc,
    payload?.cliente?.document_number,
    payload?.partner_vat,
    payload?.partner_document_number,
    payload?.partner_doc_number,
    payload?.document_number,
  ]);
}

function resolveIdentityDocumentTypeCode(
  rawType,
  documentNumber,
  fallback = DEFAULT_IDENTITY_DOC_TYPE,
) {
  const raw = String(rawType ?? "").trim();
  if (raw) {
    if (TIPO_DOCUMENTO_BY_SUNAT.has(raw)) {
      return raw;
    }

    const parsed = Number(raw);
    if (Number.isFinite(parsed) && TIPO_DOCUMENTO_BY_FACTPRO.has(parsed)) {
      return TIPO_DOCUMENTO_BY_FACTPRO.get(parsed).sunat;
    }
  }

  const cleanDoc = String(documentNumber || "").replace(/\D/g, "");
  if (cleanDoc.length === 8) {
    return "1";
  }
  if (cleanDoc.length === 11) {
    return "6";
  }

  return fallback;
}

function resolveAndValidateCustomerRuc(overrides = {}, payload = {}) {
  const rucCandidate = firstNonEmptyString([
    overrides?.cliente?.ruc,
    payload?.cliente?.ruc,
    payload?.partner_vat,
    payload?.partner_document_number,
    payload?.partner_doc_number,
    payload?.document_number,
  ]);
  const cleanRuc = String(rucCandidate || "").replace(/\D/g, "");

  if (cleanRuc.length !== 11) {
    const error = new Error(
      "Cliente RUC invalido. Para este flujo temporal envia cliente.ruc de 11 digitos.",
    );
    error.statusCode = 400;
    throw error;
  }

  if (!overrides.cliente || typeof overrides.cliente !== "object") {
    overrides.cliente = {};
  }

  overrides.cliente.ruc = cleanRuc;
  overrides.cliente.documentTypeCode = "6";
}

function saveBase64CertificateTemp(base64String, fileName = "certificado.pfx") {
  const match = base64String.match(/^data:.*;base64,(.+)$/);
  const cleanBase64 = match ? match[1] : base64String;
  const buffer = Buffer.from(cleanBase64, "base64");
  const tempDir = "uploads";

  if (!fs.existsSync(tempDir)) {
    fs.mkdirSync(tempDir, { recursive: true });
  }

  const tempPath = path.join(tempDir, `${Date.now()}-${fileName}`);
  fs.writeFileSync(tempPath, buffer);

  return tempPath;
}

function buildTestNombre() {
  return `${SUNAT_TEST_RUC}-${SUNAT_TEST_TIPO_COMPROBANTE}-${SUNAT_TEST_SERIE}-${SUNAT_TEST_CORRELATIVO}`;
}

function readSunatTestXml() {
  const xmlPath = path.join("./", SUNAT_TEST_XML_FILE);
  if (!fs.existsSync(xmlPath)) {
    const error = new Error(
      `No se encontro el XML de prueba en: ${SUNAT_TEST_XML_FILE}`,
    );
    error.statusCode = 400;
    throw error;
  }

  let xmlContent = fs.readFileSync(xmlPath, "utf8");
  xmlContent = xmlContent.replace(/\r?\n|\r/g, "").trim();
  return xmlContent;
}

function resolveSunatEmisorCredentials(
  bodyEmisor = {},
  { fallbackRuc = SUNAT_TEST_RUC } = {},
) {
  const usuarioEmisor =
    bodyEmisor.usuario_emisor ||
    process.env.SUNAT_USUARIO ||
    process.env.SUNAT_TEST_USUARIO ||
    "";
  const claveEmisor =
    bodyEmisor.clave_emisor ||
    process.env.SUNAT_CLAVE ||
    process.env.SUNAT_TEST_CLAVE ||
    "";

  if (!usuarioEmisor || !claveEmisor) {
    const error = new Error(
      "Faltan credenciales SUNAT. Envia emisor.usuario_emisor y emisor.clave_emisor o define SUNAT_USUARIO/SUNAT_CLAVE.",
    );
    error.statusCode = 400;
    throw error;
  }

  return {
    ruc: bodyEmisor.ruc || fallbackRuc,
    usuario_emisor: usuarioEmisor,
    clave_emisor: claveEmisor,
  };
}

function resolveXmlSignerOptions(body = {}) {
  const emisor =
    body?.emisor && typeof body.emisor === "object" ? body.emisor : {};

  const certificateBase64 = firstNonEmptyString([
    emisor.certificadoBase64,
    emisor.certificateBase64,
    emisor.certificado_base64,
    body?.certificadoBase64,
    body?.certificateBase64,
  ]);
  const certificatePassword = firstNonEmptyString([
    emisor.certPassword,
    emisor.cert_password,
    emisor.password_certificado,
    body?.certPassword,
    body?.cert_password,
  ]);
  const certificatePath = firstNonEmptyString([
    emisor.certPath,
    emisor.certificatePath,
    body?.certPath,
    body?.certificatePath,
  ]);

  return {
    ...(certificateBase64 ? { certificateBase64 } : {}),
    ...(certificatePassword ? { certificatePassword } : {}),
    ...(certificatePath ? { certificatePath } : {}),
  };
}

function resolveBuilderInput(body = {}) {
  if (body?.overrides && typeof body.overrides === "object") {
    return body.overrides;
  }
  if (body?.builder && typeof body.builder === "object") {
    return body.builder;
  }
  if (body?.payload && typeof body.payload === "object") {
    return body.payload;
  }
  return body;
}

function toAmountString(value, fallback = "0") {
  const number = Number(value);
  if (!Number.isFinite(number)) {
    return String(fallback);
  }
  return String(Math.round((number + Number.EPSILON) * 100) / 100);
}

function resolveDateTime(
  value,
  fallbackDate = "2025-11-23",
  fallbackTime = "11:30:00",
) {
  const raw = typeof value === "string" ? value.trim() : "";
  const date = raw.match(/^(\d{4}-\d{2}-\d{2})/)?.[1] || fallbackDate;
  const time = raw.match(/T(\d{2}:\d{2}:\d{2})/)?.[1] || fallbackTime;
  return { date, time };
}

function resolveDocId(
  value,
  fallbackSerie = SUNAT_TEST_SERIE,
  fallbackCorrelativo = SUNAT_TEST_CORRELATIVO,
) {
  const raw = String(value || "").trim();

  const slashMatch = raw.match(/^([A-Za-z]\d{3})\/\d{4}\/(\d+)$/);
  if (slashMatch) {
    const serie = slashMatch[1].toUpperCase();
    const correlativo = slashMatch[2];
    return { serie, correlativo, id: `${serie}-${correlativo}` };
  }

  const dashMatch = raw.match(/^([A-Za-z]\d{3})-(\d+)$/);
  if (dashMatch) {
    const serie = dashMatch[1].toUpperCase();
    const correlativo = dashMatch[2];
    return { serie, correlativo, id: `${serie}-${correlativo}` };
  }

  const genericMatch = raw.match(/([A-Za-z]\d{3}).*?(\d+)$/);
  if (genericMatch) {
    const serie = genericMatch[1].toUpperCase();
    const correlativo = genericMatch[2];
    return { serie, correlativo, id: `${serie}-${correlativo}` };
  }

  return {
    serie: fallbackSerie,
    correlativo: fallbackCorrelativo,
    id: `${fallbackSerie}-${fallbackCorrelativo}`,
  };
}

function resolveInvoiceTypeCode(payload = {}) {
  const fromName = String(payload?.document_type_name || "").match(
    /\((\d{2})\)/,
  )?.[1];

  if (fromName) {
    return fromName;
  }

  if (payload?.document_type_id === 1) {
    return "01";
  }

  return "01";
}

function resolveOperationCode(payload = {}) {
  const fromOperationType = String(payload?.operation_type || "")
    .trim()
    .match(/^(\d{4})$/)?.[1];
  if (fromOperationType) {
    return fromOperationType;
  }

  const fromC51 = String(payload?.c51_name || "").match(/\[(\d{4})\]/)?.[1];
  if (fromC51) {
    return fromC51;
  }

  if (Number(payload?.edi_operation_id) === 1) {
    return "0101";
  }

  return "0101";
}

function resolveUnitCode(uomName = "") {
  const value = normalizeText(uomName);
  if (!value) {
    return "NIU";
  }

  if (UOM_BY_NAME.has(value)) {
    return UOM_BY_NAME.get(value);
  }

  for (const [unitName, code] of UOM_BY_NAME.entries()) {
    if (unitName && value.includes(unitName)) {
      return code;
    }
  }

  if (value === "kg" || value.includes("kilo")) {
    return "KGM";
  }
  if (value === "g" || value.includes("gram")) {
    return "GRM";
  }
  if (value === "l" || value.includes("lt") || value.includes("litro")) {
    return "LTR";
  }
  if (value.includes("caja")) {
    return "BX";
  }

  return "NIU";
}

function resolveTaxSchemeIdFromContext({ tax = {}, taxGroupName = "" } = {}) {
  const explicitSunatId = firstNonEmptyString([
    tax?.tax_scheme_id,
    tax?.tax_sunat_id,
    tax?.tributo_sunat,
    tax?.sunat,
  ]).match(/^\d{4}$/)?.[0];
  if (explicitSunatId) {
    return explicitSunatId;
  }

  const taxFactpro = Number(tax?.tax_id);
  if (Number.isFinite(taxFactpro) && TRIBUTO_BY_FACTPRO.has(taxFactpro)) {
    return TRIBUTO_BY_FACTPRO.get(taxFactpro).sunat;
  }

  const group = normalizeText(taxGroupName);
  if (group.includes("bolsa") || group.includes("icbper")) {
    return "7152";
  }
  if (group.includes("isc")) {
    return "2000";
  }
  if (group.includes("exo") || group.includes("exoner")) {
    return "9997";
  }
  if (group.includes("inaf") || group === "ina") {
    return "9998";
  }

  return "1000";
}

function resolveAfectacionCodeFromContext({
  tax = {},
  taxGroupName = "",
  taxSchemeId = "1000",
} = {}) {
  const explicitAfectacion = firstNonEmptyString([
    tax?.tax_exemption_reason_code,
    tax?.afectacion_igv_sunat,
    tax?.afectacion_igv_code,
  ]);
  if (explicitAfectacion && AFECTACION_BY_SUNAT.has(explicitAfectacion)) {
    return explicitAfectacion;
  }

  const afectacionFactpro = Number(
    firstNonEmptyString([
      tax?.afectacion_igv_factpro,
      tax?.afectacion_igv_id,
      tax?.tax_affectation_id,
    ]),
  );
  if (
    Number.isFinite(afectacionFactpro) &&
    AFECTACION_BY_FACTPRO.has(afectacionFactpro)
  ) {
    return AFECTACION_BY_FACTPRO.get(afectacionFactpro).sunat;
  }

  if (taxSchemeId === "9997") {
    return "20";
  }
  if (taxSchemeId === "9998") {
    return "30";
  }

  const group = normalizeText(taxGroupName);
  if (group.includes("export")) {
    return "40";
  }
  if (group.includes("gratuit")) {
    return "21";
  }
  if (group.includes("exo") || group.includes("exoner")) {
    return "20";
  }
  if (group.includes("inaf") || group === "ina") {
    return "30";
  }

  return "10";
}

function resolveTaxCatalogData({
  tax = {},
  taxGroupName = "IGV",
  percentage,
} = {}) {
  const taxSchemeId = resolveTaxSchemeIdFromContext({ tax, taxGroupName });
  const taxScheme =
    TAX_SCHEME_BY_SUNAT[taxSchemeId] || TAX_SCHEME_BY_SUNAT["1000"];

  if (taxSchemeId === "7152") {
    return {
      categoryId: undefined,
      taxExemptionReasonCode: undefined,
      defaultPercent: undefined,
      taxScheme,
    };
  }

  const taxExemptionReasonCode = resolveAfectacionCodeFromContext({
    tax,
    taxGroupName,
    taxSchemeId,
  });
  const categoryId = TAX_CATEGORY_BY_AFECTACION[taxExemptionReasonCode] || "S";
  const catalogAfectacion = AFECTACION_BY_SUNAT.get(taxExemptionReasonCode);

  const defaultPercent =
    percentage !== undefined && percentage !== null
      ? percentage
      : catalogAfectacion?.porcentaje;

  return {
    categoryId,
    taxExemptionReasonCode,
    defaultPercent,
    taxScheme,
  };
}

function buildTaxSubtotal({
  taxableAmount,
  taxAmount,
  currencyID,
  percentage,
  taxGroupName,
  tax,
}) {
  const taxCatalog = resolveTaxCatalogData({
    tax,
    taxGroupName,
    percentage,
  });
  const resolvedPercent =
    percentage !== undefined && percentage !== null
      ? percentage
      : taxCatalog.defaultPercent;

  return {
    taxableAmount: toAmountString(taxableAmount),
    taxAmount: toAmountString(taxAmount),
    currencyID,
    taxCategory: {
      id: taxCatalog.categoryId,
      idAttrs: {
        schemeID: "UN/ECE 5305",
        schemeName: "Tax Category Identifier",
        schemeAgencyName: "United Nations Economic Commission for Europe",
      },
      percent:
        taxCatalog.categoryId &&
        resolvedPercent !== undefined &&
        resolvedPercent !== null
          ? toAmountString(resolvedPercent)
          : undefined,
      taxExemptionReasonCode: taxCatalog.taxExemptionReasonCode || undefined,
      taxExemptionReasonCodeAttrs: {
        listAgencyName: "PE:SUNAT",
        listName: "Afectacion del IGV",
        listURI: "urn:pe:gob:sunat:cpe:see:gem:catalogos:catalogo07",
      },
      taxScheme: {
        id: taxCatalog.taxScheme.id,
        idAttrs: {
          schemeID: "UN/ECE 5153",
          schemeName: "Codigo de tributos",
          schemeAgencyName: "PE:SUNAT",
        },
        name: taxCatalog.taxScheme.name,
        taxTypeCode: taxCatalog.taxScheme.taxTypeCode,
      },
    },
  };
}

function buildInvoiceItemsFromMoveLines(moveLines = [], currencyID = "PEN") {
  const validLines = Array.isArray(moveLines)
    ? moveLines.filter((line) => line?.type === "L")
    : [];

  return validLines.map((line, index) => {
    const quantity = Number(line?.quantity) || 0;
    const lineAmountUntaxed = Number(
      line?.amount_untaxed_total ?? line?.amount_untaxed ?? 0,
    );
    const lineAmountTax = Number(
      line?.amount_tax_total ?? line?.amount_tax ?? 0,
    );
    const lineAmountWithTax = Number(
      line?.amount_withtaxed_total ?? line?.amount_withtaxed ?? 0,
    );
    const taxes = Array.isArray(line?.move_lines_taxes)
      ? line.move_lines_taxes
      : [];
    const safeQuantity = quantity > 0 ? quantity : 1;
    const unitPriceWithTax =
      lineAmountWithTax > 0
        ? lineAmountWithTax / safeQuantity
        : Number(line?.price_unit ?? 0);

    const subtotals =
      taxes.length > 0
        ? taxes.map((tax) =>
            buildTaxSubtotal({
              taxableAmount: lineAmountUntaxed,
              taxAmount: tax?.amount ?? 0,
              currencyID,
              percentage: tax?.percentage,
              taxGroupName: tax?.tax_group_name,
              tax,
            }),
          )
        : [
            buildTaxSubtotal({
              taxableAmount: lineAmountUntaxed,
              taxAmount: lineAmountTax,
              currencyID,
              percentage: 18,
              taxGroupName: "IGV",
              tax: { tax_group_name: "IGV" },
            }),
          ];

    return {
      id: String(index + 1),
      quantity: toAmountString(quantity),
      unitCode: resolveUnitCode(line?.uom_name),
      unitCodeListID: "UN/ECE rec 20",
      unitCodeListAgencyName: "United Nations Economic Commission for Europe",
      lineExtensionAmount: toAmountString(lineAmountUntaxed),
      currencyID,
      pricingReference: {
        priceAmount: toAmountString(unitPriceWithTax),
        currencyID,
        priceTypeCode: "01",
        priceTypeCodeAttrs: {
          listName: "Tipo de Precio",
          listAgencyName: "PE:SUNAT",
          listURI: "urn:pe:gob:sunat:cpe:see:gem:catalogos:catalogo16",
        },
      },
      taxTotal: {
        taxAmount: toAmountString(lineAmountTax),
        currencyID,
        subtotals,
      },
      item: {
        description: line?.name || "ITEM",
        sellersItemId: String(line?.product_id || line?.line_id || index + 1),
        classificationCode: "10191509",
        classificationAttrs: {
          listID: "UNSPSC",
          listAgencyName: "GS1 US",
          listName: "Item Classification",
        },
      },
      price: {
        amount: toAmountString(line?.price_unit ?? 0),
        currencyID,
      },
    };
  });
}

function buildInvoiceTaxTotalFromMoveLines(payload = {}, currencyID = "PEN") {
  const moveLines = Array.isArray(payload?.move_lines)
    ? payload.move_lines
    : [];
  const validLines = moveLines.filter((line) => line?.type === "L");
  const summary = new Map();

  for (const line of validLines) {
    const lineTaxable = Number(
      line?.amount_untaxed_total ?? line?.amount_untaxed ?? 0,
    );
    const lineTaxes = Array.isArray(line?.move_lines_taxes)
      ? line.move_lines_taxes
      : [];

    if (lineTaxes.length === 0) {
      continue;
    }

    for (const tax of lineTaxes) {
      const key = String(tax?.tax_group_name || "IGV").toUpperCase();
      if (!summary.has(key)) {
        summary.set(key, {
          taxableAmount: 0,
          taxAmount: 0,
          percentage: tax?.percentage,
          taxGroupName: tax?.tax_group_name || "IGV",
          tax,
        });
      }

      const current = summary.get(key);
      current.taxableAmount += lineTaxable;
      current.taxAmount += Number(tax?.amount ?? 0);
    }
  }

  let subtotals = Array.from(summary.values()).map((item) =>
    buildTaxSubtotal({
      taxableAmount: item.taxableAmount,
      taxAmount: item.taxAmount,
      currencyID,
      percentage: item.percentage,
      taxGroupName: item.taxGroupName,
      tax: item.tax,
    }),
  );

  if (subtotals.length === 0) {
    subtotals = [
      buildTaxSubtotal({
        taxableAmount: payload?.amount_untaxed ?? 0,
        taxAmount: payload?.amount_tax ?? 0,
        currencyID,
        percentage: 18,
        taxGroupName: "IGV",
        tax: { tax_group_name: "IGV" },
      }),
    ];
  }

  return {
    taxAmount: toAmountString(payload?.amount_tax ?? 0),
    currencyID,
    subtotals,
  };
}

function buildExternalPaymentTerms(payload = {}) {
  const paymentTermId = String(payload?.payment_term_id || "").trim();
  const paymentMeansId = paymentTermId ? "Credito" : "Contado";
  const currencyID = resolveCurrencyCode(payload?.currency_name, "PEN");
  const terms = [
    {
      id: "FormaPago",
      paymentMeansId,
    },
  ];

  if (paymentMeansId === "Contado") {
    terms[0].amount = toAmountString(payload?.amount_withtaxed ?? 0);
    terms[0].currencyID = currencyID;
  }

  const firstPayment = Array.isArray(payload?.payments)
    ? payload.payments.find((payment) => payment)
    : undefined;
  const paymentMethodFactpro = Number(firstPayment?.payment_method_id);
  if (
    Number.isFinite(paymentMethodFactpro) &&
    MEDIO_PAGO_BY_FACTPRO.has(paymentMethodFactpro)
  ) {
    terms[0].catalog59Code =
      MEDIO_PAGO_BY_FACTPRO.get(paymentMethodFactpro).fiscal;
  }

  return terms;
}

function adaptExternalFacturaPayload(payload = {}) {
  const issueDateTime = resolveDateTime(payload?.invoice_date);
  const docData = resolveDocId(payload?.name, "F001", "1");
  const currencyID = resolveCurrencyCode(payload?.currency_name, "PEN");
  const items = buildInvoiceItemsFromMoveLines(payload?.move_lines, currencyID);
  const amountUntaxed = toAmountString(payload?.amount_untaxed ?? 0);
  const amountTaxed = toAmountString(payload?.amount_withtaxed ?? 0);
  const partnerName = firstNonEmptyString([
    payload?.partner_name,
    payload?.cliente?.razonSocial,
    payload?.cliente?.nombreComercial,
  ]);
  const emisorRuc = firstNonEmptyString([
    payload?.emisor?.ruc,
    payload?.company_vat,
  ]);
  const emisorName = firstNonEmptyString([
    payload?.emisor?.razonSocial,
    payload?.emisor?.razon_social,
    payload?.emisor?.nombreComercial,
    payload?.company_name,
  ]);
  const customerDocumentNumber = resolveCustomerDocumentNumber(payload);
  const customerDocumentType = resolveIdentityDocumentTypeCode(
    firstNonEmptyString([
      payload?.cliente?.documentTypeCode,
      payload?.cliente?.document_type_code,
      payload?.partner_document_type_code,
      payload?.partner_document_type_id,
      payload?.partner_document_type,
    ]),
    customerDocumentNumber,
    resolveInvoiceTypeCode(payload) === "01" ? "6" : "1",
  );
  const operationCode = resolveOperationCode(payload);
  const invoiceTypeCode = resolveInvoiceTypeCode(payload);
  const ublVersionId = firstNonEmptyString([
    payload?.ublVersionId,
    payload?.ubl_version_id,
    payload?.cabecera?.ublVersionId,
    payload?.cabecera?.ubl_version_id,
  ]);
  const customizationId = firstNonEmptyString([
    payload?.customizationId,
    payload?.customization_id,
    payload?.cabecera?.customizationId,
    payload?.cabecera?.customization_id,
  ]);
  const resolvedUblVersionId = ublVersionId || "2.1";
  const resolvedCustomizationId = customizationId || "2.0";

  return {
    cabecera: {
      ublVersionId: resolvedUblVersionId,
      customizationId: resolvedCustomizationId,
      id: docData.id,
      issueDate: issueDateTime.date,
      issueTime: issueDateTime.time,
      profileId: operationCode,
      invoiceTypeCode,
      invoiceTypeCodeAttrs: {
        listID: operationCode,
      },
      documentCurrencyCode: currencyID,
      lineCountNumeric: String(items.length),
    },
    signature: {
      id: docData.id,
      ...(emisorRuc ? { partyId: emisorRuc } : {}),
      ...(emisorName ? { partyName: emisorName } : {}),
    },
    ...(emisorRuc || emisorName
      ? {
          emisor: {
            ...(emisorRuc ? { ruc: emisorRuc } : {}),
            ...(emisorName
              ? { nombreComercial: emisorName, razonSocial: emisorName }
              : {}),
            documentTypeCode: "6",
          },
        }
      : {}),
    ...(partnerName
      ? {
          cliente: {
            nombreComercial: partnerName,
            razonSocial: partnerName,
            ...(customerDocumentNumber ? { ruc: customerDocumentNumber } : {}),
            documentTypeCode: customerDocumentType,
          },
        }
      : {}),
    ...(!partnerName && customerDocumentNumber
      ? {
          cliente: {
            ruc: customerDocumentNumber,
            documentTypeCode: customerDocumentType,
          },
        }
      : {}),
    paymentTerms: buildExternalPaymentTerms(payload),
    taxTotal: buildInvoiceTaxTotalFromMoveLines(payload, currencyID),
    legalMonetaryTotal: {
      lineExtensionAmount: amountUntaxed,
      taxInclusiveAmount: amountTaxed,
      payableAmount: amountTaxed,
      currencyID,
    },
    items,
  };
}

function resolveFacturaBuilderOverrides(inputPayload = {}) {
  if (!inputPayload || typeof inputPayload !== "object") {
    return inputPayload;
  }

  const isBuilderShape =
    typeof inputPayload?.cabecera === "object" ||
    Array.isArray(inputPayload?.items);

  if (isBuilderShape) {
    return inputPayload;
  }

  const looksLikeExternalInvoice =
    typeof inputPayload?.name === "string" &&
    Array.isArray(inputPayload?.move_lines);

  if (!looksLikeExternalInvoice) {
    return inputPayload;
  }

  return adaptExternalFacturaPayload(inputPayload);
}

function resolveNombreFromBuilderPayload(
  payload = {},
  {
    fallbackTipoComprobante = SUNAT_TEST_TIPO_COMPROBANTE,
    fallbackSerie = SUNAT_TEST_SERIE,
    fallbackCorrelativo = SUNAT_TEST_CORRELATIVO,
  } = {},
) {
  const ruc = payload?.emisor?.ruc || SUNAT_TEST_RUC;
  const tipoComprobante =
    payload?.cabecera?.invoiceTypeCode ||
    payload?.cabecera?.creditNoteTypeCode ||
    payload?.cabecera?.debitNoteTypeCode ||
    fallbackTipoComprobante;
  const docIdData = resolveDocId(
    payload?.cabecera?.id,
    fallbackSerie,
    fallbackCorrelativo,
  );
  const serieRaw = docIdData.serie;
  const correlativoRaw = docIdData.correlativo;
  const serie = serieRaw || fallbackSerie;
  const correlativo = correlativoRaw || fallbackCorrelativo;

  return {
    ruc,
    tipoComprobante,
    serie,
    correlativo,
    nombre: `${ruc}-${tipoComprobante}-${serie}-${correlativo}`,
  };
}
export async function enviarFactura(req, res, next) {
  let requestTempPath;
  let nombre;
  try {
    const data = req.body;

    const { emisor, cabecera } = data;

    nombre = `${emisor.ruc}-${cabecera.tipo_comprobante}-${cabecera.serie}-${cabecera.correlativo}`;

    const xmlPath = path.join("./", "20100100100-01-F001-175.xml");
    let xmlContent = fs.readFileSync(xmlPath, "utf8");
    xmlContent = xmlContent.replace(/\r?\n|\r/g, "").trim();

    const signerOptions = resolveXmlSignerOptions(req.body || {});
    const xmlFirmado = await signXML(xmlContent, signerOptions);
    const zipBuffer = makeZip(nombre, xmlFirmado);
    const zipBase64 = zipBuffer.toString("base64");
    requestTempPath = saveTempZip(zipBuffer, `request-${nombre}.zip`);

    const cdrBase64 = await sendToSunat(zipBase64, nombre, emisor);
    const cdrZipBuffer = Buffer.from(cdrBase64, "base64");
    const responseTempPath = saveTempZip(
      cdrZipBuffer,
      `response-${nombre}.zip`,
    );

    let uploadResult;
    try {
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
    } catch (uploadError) {
      uploadResult = {
        success: false,
        message:
          uploadError?.message ||
          "Error subiendo archivos a Cloudflare R2. Se mantienen en disco.",
        requestTempPath,
        responseTempPath,
      };
    }

    const cdrArchivos = unzipCDR(
      cdrBase64,
      emisor?.ruc,
      cabecera?.serie,
      cabecera?.correlativo,
    );

    res.json({
      success: true,
      xml: xmlFirmado,
      zip: zipBase64,
      cdrBase64,
      cdr: cdrArchivos,
      uploadResult: uploadResult,
      toDb: {
        xml_request: xmlFirmado,
        xml_response: cdrArchivos.xmlContent,
        code_sunat: cdrArchivos.responseCode,
        description_sunat: cdrArchivos.description,
        date: cdrArchivos.date,
      },
    });
  } catch (error) {
    const status = error.statusCode || error.status || 500;

    let failedUpload;
    if (requestTempPath && nombre) {
      try {
        const requestUpload = await uploadFileFromDisk(
          requestTempPath,
          `request-${nombre}.zip`,
          r2Prefixes.request,
        );
        failedUpload = {
          success: true,
          request: requestUpload,
          requestTempPath,
        };
      } catch (uploadError) {
        failedUpload = {
          success: false,
          message:
            uploadError?.message ||
            "Error subiendo archivo de request a Cloudflare R2.",
          requestTempPath,
        };
      }
    }

    return res.status(status).json({
      success: false,
      message: error.message || "Error procesando factura",
      ...(error.sunatCode ? { sunatCode: error.sunatCode } : {}),
      ...(error.details ? { details: error.details } : {}),
      ...(error.sentSoap ? { xmlRequest: error.sentSoap } : {}),
      ...(failedUpload ? { uploadResult: failedUpload } : {}),
    });
  }
}

export async function enviarFacturaPrueba(req, res, next) {
  let requestTempPath;
  const nombre = buildTestNombre();

  try {
    const emisor = resolveSunatEmisorCredentials(req.body?.emisor || {});
    const xmlContent = readSunatTestXml();

    const signerOptions = resolveXmlSignerOptions(req.body || {});
    const xmlFirmado = await signXML(xmlContent, signerOptions);
    const zipBuffer = makeZip(nombre, xmlFirmado);
    const zipBase64 = zipBuffer.toString("base64");
    requestTempPath = saveTempZip(zipBuffer, `request-${nombre}.zip`);

    const cdrBase64 = await sendToSunat(zipBase64, nombre, emisor);
    const cdrZipBuffer = Buffer.from(cdrBase64, "base64");
    const responseTempPath = saveTempZip(
      cdrZipBuffer,
      `response-${nombre}.zip`,
    );

    let uploadResult;
    try {
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
    } catch (uploadError) {
      uploadResult = {
        success: false,
        message:
          uploadError?.message ||
          "Error subiendo archivos a Cloudflare R2. Se mantienen en disco.",
        requestTempPath,
        responseTempPath,
      };
    }

    const cdrArchivos = unzipCDR(
      cdrBase64,
      emisor.ruc,
      SUNAT_TEST_SERIE,
      SUNAT_TEST_CORRELATIVO,
    );

    return res.json({
      success: true,
      flow: "factura_prueba",
      sourceXml: SUNAT_TEST_XML_FILE,
      nombre,
      xml: xmlFirmado,
      zip: zipBase64,
      cdrBase64,
      cdr: cdrArchivos,
      uploadResult,
      toDb: {
        xml_request: xmlFirmado,
        xml_response: cdrArchivos.xmlContent,
        code_sunat: cdrArchivos.responseCode,
        description_sunat: cdrArchivos.description,
        date: cdrArchivos.date,
      },
    });
  } catch (error) {
    const status = error.statusCode || error.status || 500;

    let failedUpload;
    if (requestTempPath) {
      try {
        const requestUpload = await uploadFileFromDisk(
          requestTempPath,
          `request-${nombre}.zip`,
          r2Prefixes.request,
        );
        failedUpload = {
          success: true,
          request: requestUpload,
          requestTempPath,
        };
      } catch (uploadError) {
        failedUpload = {
          success: false,
          message:
            uploadError?.message ||
            "Error subiendo archivo de request a Cloudflare R2.",
          requestTempPath,
        };
      }
    }

    return res.status(status).json({
      success: false,
      flow: "factura_prueba",
      message: error.message || "Error procesando factura de prueba",
      ...(error.sunatCode ? { sunatCode: error.sunatCode } : {}),
      ...(error.details ? { details: error.details } : {}),
      ...(error.sentSoap ? { xmlRequest: error.sentSoap } : {}),
      ...(failedUpload ? { uploadResult: failedUpload } : {}),
    });
  }
}

export async function enviarFacturaBuilder(req, res, next) {
  let requestTempPath;
  let nombre;
  let docData;

  try {
    const inputPayload = resolveBuilderInput(req.body || {});
    const overrides = resolveFacturaBuilderOverrides(inputPayload);
    resolveAndValidateCustomerRuc(overrides, inputPayload);
    const operationCode = resolveOperationCode(inputPayload);

    if (!overrides.cabecera || typeof overrides.cabecera !== "object") {
      overrides.cabecera = {};
    }
    overrides.cabecera.ublVersionId = "2.1";
    overrides.cabecera.customizationId = "2.0";
    if (!overrides.cabecera.profileId) {
      overrides.cabecera.profileId = operationCode;
    }
    overrides.cabecera.invoiceTypeCodeAttrs = {
      ...(overrides.cabecera.invoiceTypeCodeAttrs || {}),
      listID: overrides.cabecera.invoiceTypeCodeAttrs?.listID || operationCode,
    };

    const payloadForNombre = req.body?.emisor?.ruc
      ? {
          ...overrides,
          emisor: {
            ...(overrides?.emisor || {}),
            ruc: req.body.emisor.ruc,
          },
        }
      : overrides;

    docData = resolveNombreFromBuilderPayload(payloadForNombre);
    nombre = docData.nombre;

    const emisorCreds = resolveSunatEmisorCredentials(req.body?.emisor || {}, {
      fallbackRuc: docData.ruc,
    });
    const signerOptions = resolveXmlSignerOptions(req.body || {});

    const xmlContent = buildInvoiceXML(overrides);
    const xmlFirmado = await signXML(xmlContent, signerOptions);
    const zipBuffer = makeZip(nombre, xmlFirmado);
    const zipBase64 = zipBuffer.toString("base64");
    requestTempPath = saveTempZip(zipBuffer, `request-${nombre}.zip`);

    const cdrBase64 = await sendToSunat(zipBase64, nombre, emisorCreds);
    const cdrZipBuffer = Buffer.from(cdrBase64, "base64");
    const responseTempPath = saveTempZip(
      cdrZipBuffer,
      `response-${nombre}.zip`,
    );

    let uploadResult;
    try {
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
    } catch (uploadError) {
      uploadResult = {
        success: false,
        message:
          uploadError?.message ||
          "Error subiendo archivos a Cloudflare R2. Se mantienen en disco.",
        requestTempPath,
        responseTempPath,
      };
    }

    const cdrArchivos = unzipCDR(
      cdrBase64,
      docData.ruc,
      docData.serie,
      docData.correlativo,
    );

    return res.json({
      success: true,
      flow: "factura_builder",
      nombre,
      xml: xmlFirmado,
      zip: zipBase64,
      cdrBase64,
      cdr: cdrArchivos,
      uploadResult,
      toDb: {
        xml_request: xmlFirmado,
        xml_response: cdrArchivos.xmlContent,
        code_sunat: cdrArchivos.responseCode,
        description_sunat: cdrArchivos.description,
        date: cdrArchivos.date,
      },
    });
  } catch (error) {
    const status = error.statusCode || error.status || 500;

    let failedUpload;
    if (requestTempPath && nombre) {
      try {
        const requestUpload = await uploadFileFromDisk(
          requestTempPath,
          `request-${nombre}.zip`,
          r2Prefixes.request,
        );
        failedUpload = {
          success: true,
          request: requestUpload,
          requestTempPath,
        };
      } catch (uploadError) {
        failedUpload = {
          success: false,
          message:
            uploadError?.message ||
            "Error subiendo archivo de request a Cloudflare R2.",
          requestTempPath,
        };
      }
    }

    return res.status(status).json({
      success: false,
      flow: "factura_builder",
      message: error.message || "Error procesando factura con builder",
      ...(error.sunatCode ? { sunatCode: error.sunatCode } : {}),
      ...(error.details ? { details: error.details } : {}),
      ...(error.sentSoap ? { xmlRequest: error.sentSoap } : {}),
      ...(failedUpload ? { uploadResult: failedUpload } : {}),
    });
  }
}

export async function enviarBoletaBuilder(req, res, next) {
  let requestTempPath;
  let nombre;
  let docData;

  try {
    const overrides = resolveBuilderInput(req.body || {});
    resolveAndValidateCustomerRuc(overrides, req.body || {});
    if (!overrides.cabecera || typeof overrides.cabecera !== "object") {
      overrides.cabecera = {};
    }

    if (!overrides.cabecera.invoiceTypeCode) {
      overrides.cabecera.invoiceTypeCode = "03";
    }

    docData = resolveNombreFromBuilderPayload(overrides, {
      fallbackTipoComprobante: "03",
      fallbackSerie: "B001",
    });
    nombre = docData.nombre;

    const emisorCreds = resolveSunatEmisorCredentials(req.body?.emisor || {}, {
      fallbackRuc: docData.ruc,
    });
    const signerOptions = resolveXmlSignerOptions(req.body || {});

    const xmlContent = buildBoletaXML(overrides);
    const xmlFirmado = await signXML(xmlContent, signerOptions);
    const zipBuffer = makeZip(nombre, xmlFirmado);
    const zipBase64 = zipBuffer.toString("base64");
    requestTempPath = saveTempZip(zipBuffer, `request-${nombre}.zip`);

    const cdrBase64 = await sendToSunat(zipBase64, nombre, emisorCreds);
    const cdrZipBuffer = Buffer.from(cdrBase64, "base64");
    const responseTempPath = saveTempZip(
      cdrZipBuffer,
      `response-${nombre}.zip`,
    );

    let uploadResult;
    try {
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
    } catch (uploadError) {
      uploadResult = {
        success: false,
        message:
          uploadError?.message ||
          "Error subiendo archivos a Cloudflare R2. Se mantienen en disco.",
        requestTempPath,
        responseTempPath,
      };
    }

    const cdrArchivos = unzipCDR(
      cdrBase64,
      docData.ruc,
      docData.serie,
      docData.correlativo,
    );

    return res.json({
      success: true,
      flow: "boleta_builder",
      nombre,
      xml: xmlFirmado,
      zip: zipBase64,
      cdrBase64,
      cdr: cdrArchivos,
      uploadResult,
      toDb: {
        xml_request: xmlFirmado,
        xml_response: cdrArchivos.xmlContent,
        code_sunat: cdrArchivos.responseCode,
        description_sunat: cdrArchivos.description,
        date: cdrArchivos.date,
      },
    });
  } catch (error) {
    const status = error.statusCode || error.status || 500;

    let failedUpload;
    if (requestTempPath && nombre) {
      try {
        const requestUpload = await uploadFileFromDisk(
          requestTempPath,
          `request-${nombre}.zip`,
          r2Prefixes.request,
        );
        failedUpload = {
          success: true,
          request: requestUpload,
          requestTempPath,
        };
      } catch (uploadError) {
        failedUpload = {
          success: false,
          message:
            uploadError?.message ||
            "Error subiendo archivo de request a Cloudflare R2.",
          requestTempPath,
        };
      }
    }

    return res.status(status).json({
      success: false,
      flow: "boleta_builder",
      message: error.message || "Error procesando boleta con builder",
      ...(error.sunatCode ? { sunatCode: error.sunatCode } : {}),
      ...(error.details ? { details: error.details } : {}),
      ...(error.sentSoap ? { xmlRequest: error.sentSoap } : {}),
      ...(failedUpload ? { uploadResult: failedUpload } : {}),
    });
  }
}

export async function enviarNotaCreditoBuilder(req, res, next) {
  let requestTempPath;
  let nombre;
  let docData;

  try {
    const overrides = resolveBuilderInput(req.body || {});
    if (!overrides.cabecera || typeof overrides.cabecera !== "object") {
      overrides.cabecera = {};
    }

    if (!overrides.cabecera.creditNoteTypeCode) {
      overrides.cabecera.creditNoteTypeCode = "07";
    }

    docData = resolveNombreFromBuilderPayload(overrides, {
      fallbackTipoComprobante: "07",
      fallbackSerie: "FC01",
    });
    nombre = docData.nombre;

    const emisorCreds = resolveSunatEmisorCredentials(req.body?.emisor || {}, {
      fallbackRuc: docData.ruc,
    });
    const signerOptions = resolveXmlSignerOptions(req.body || {});

    const xmlContent = buildCreditNoteXML(overrides);
    const xmlFirmado = await signXML(xmlContent, signerOptions);
    const zipBuffer = makeZip(nombre, xmlFirmado);
    const zipBase64 = zipBuffer.toString("base64");
    requestTempPath = saveTempZip(zipBuffer, `request-${nombre}.zip`);

    const cdrBase64 = await sendToSunat(zipBase64, nombre, emisorCreds);
    const cdrZipBuffer = Buffer.from(cdrBase64, "base64");
    const responseTempPath = saveTempZip(
      cdrZipBuffer,
      `response-${nombre}.zip`,
    );

    let uploadResult;
    try {
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
    } catch (uploadError) {
      uploadResult = {
        success: false,
        message:
          uploadError?.message ||
          "Error subiendo archivos a Cloudflare R2. Se mantienen en disco.",
        requestTempPath,
        responseTempPath,
      };
    }

    const cdrArchivos = unzipCDR(
      cdrBase64,
      docData.ruc,
      docData.serie,
      docData.correlativo,
    );

    return res.json({
      success: true,
      flow: "nota_credito_builder",
      nombre,
      xml: xmlFirmado,
      zip: zipBase64,
      cdrBase64,
      cdr: cdrArchivos,
      uploadResult,
      toDb: {
        xml_request: xmlFirmado,
        xml_response: cdrArchivos.xmlContent,
        code_sunat: cdrArchivos.responseCode,
        description_sunat: cdrArchivos.description,
        date: cdrArchivos.date,
      },
    });
  } catch (error) {
    const status = error.statusCode || error.status || 500;

    let failedUpload;
    if (requestTempPath && nombre) {
      try {
        const requestUpload = await uploadFileFromDisk(
          requestTempPath,
          `request-${nombre}.zip`,
          r2Prefixes.request,
        );
        failedUpload = {
          success: true,
          request: requestUpload,
          requestTempPath,
        };
      } catch (uploadError) {
        failedUpload = {
          success: false,
          message:
            uploadError?.message ||
            "Error subiendo archivo de request a Cloudflare R2.",
          requestTempPath,
        };
      }
    }

    return res.status(status).json({
      success: false,
      flow: "nota_credito_builder",
      message: error.message || "Error procesando nota de credito con builder",
      ...(error.sunatCode ? { sunatCode: error.sunatCode } : {}),
      ...(error.details ? { details: error.details } : {}),
      ...(error.sentSoap ? { xmlRequest: error.sentSoap } : {}),
      ...(failedUpload ? { uploadResult: failedUpload } : {}),
    });
  }
}

export async function enviarNotaDebitoBuilder(req, res, next) {
  let requestTempPath;
  let nombre;
  let docData;

  try {
    const overrides = resolveBuilderInput(req.body || {});
    if (!overrides.cabecera || typeof overrides.cabecera !== "object") {
      overrides.cabecera = {};
    }

    if (!overrides.cabecera.debitNoteTypeCode) {
      overrides.cabecera.debitNoteTypeCode = "08";
    }

    docData = resolveNombreFromBuilderPayload(overrides, {
      fallbackTipoComprobante: "08",
      fallbackSerie: "FD01",
    });
    nombre = docData.nombre;

    const emisorCreds = resolveSunatEmisorCredentials(req.body?.emisor || {}, {
      fallbackRuc: docData.ruc,
    });
    const signerOptions = resolveXmlSignerOptions(req.body || {});

    const xmlContent = buildDebitNoteXML(overrides);
    const xmlFirmado = await signXML(xmlContent, signerOptions);
    const zipBuffer = makeZip(nombre, xmlFirmado);
    const zipBase64 = zipBuffer.toString("base64");
    requestTempPath = saveTempZip(zipBuffer, `request-${nombre}.zip`);

    const cdrBase64 = await sendToSunat(zipBase64, nombre, emisorCreds);
    const cdrZipBuffer = Buffer.from(cdrBase64, "base64");
    const responseTempPath = saveTempZip(
      cdrZipBuffer,
      `response-${nombre}.zip`,
    );

    let uploadResult;
    try {
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
    } catch (uploadError) {
      uploadResult = {
        success: false,
        message:
          uploadError?.message ||
          "Error subiendo archivos a Cloudflare R2. Se mantienen en disco.",
        requestTempPath,
        responseTempPath,
      };
    }

    const cdrArchivos = unzipCDR(
      cdrBase64,
      docData.ruc,
      docData.serie,
      docData.correlativo,
    );

    return res.json({
      success: true,
      flow: "nota_debito_builder",
      nombre,
      xml: xmlFirmado,
      zip: zipBase64,
      cdrBase64,
      cdr: cdrArchivos,
      uploadResult,
      toDb: {
        xml_request: xmlFirmado,
        xml_response: cdrArchivos.xmlContent,
        code_sunat: cdrArchivos.responseCode,
        description_sunat: cdrArchivos.description,
        date: cdrArchivos.date,
      },
    });
  } catch (error) {
    const status = error.statusCode || error.status || 500;

    let failedUpload;
    if (requestTempPath && nombre) {
      try {
        const requestUpload = await uploadFileFromDisk(
          requestTempPath,
          `request-${nombre}.zip`,
          r2Prefixes.request,
        );
        failedUpload = {
          success: true,
          request: requestUpload,
          requestTempPath,
        };
      } catch (uploadError) {
        failedUpload = {
          success: false,
          message:
            uploadError?.message ||
            "Error subiendo archivo de request a Cloudflare R2.",
          requestTempPath,
        };
      }
    }

    return res.status(status).json({
      success: false,
      flow: "nota_debito_builder",
      message: error.message || "Error procesando nota de debito con builder",
      ...(error.sunatCode ? { sunatCode: error.sunatCode } : {}),
      ...(error.details ? { details: error.details } : {}),
      ...(error.sentSoap ? { xmlRequest: error.sentSoap } : {}),
      ...(failedUpload ? { uploadResult: failedUpload } : {}),
    });
  }
}

export async function uploadSunatCertificate(req, res, next) {
  const file = req.file;
  const base64 =
    req.body?.base64 ||
    req.body?.certificadoBase64 ||
    req.body?.certificateBase64;

  if (!file && !base64) {
    return res.status(400).json({
      success: false,
      message:
        "Debes adjuntar el certificado en el campo 'certificado' (archivo) o enviar 'base64'/'certificadoBase64' en el cuerpo.",
    });
  }

  let tempPath = file?.path;
  const fileName =
    file?.originalname || req.body?.fileName || "certificado.pfx";

  if (!tempPath && base64) {
    try {
      tempPath = saveBase64CertificateTemp(base64, fileName);
    } catch (error) {
      return res.status(400).json({
        success: false,
        message: "Base64 inválido",
        error: error.message,
      });
    }
  }

  try {
    const uploaded = await uploadCertificateFromDisk(tempPath, fileName);

    if (fs.existsSync(tempPath)) {
      fs.unlinkSync(tempPath);
    }

    return res.json({
      success: true,
      message: "Certificado subido correctamente",
      certificate: uploaded,
      url: uploaded.url,
    });
  } catch (error) {
    if (fs.existsSync(tempPath)) {
      fs.unlinkSync(tempPath);
    }
    return next(error);
  }
}

export async function deleteFileToDrive(req, res, next) {
  try {
    const key = req.body?.key || req.body?.fileId;

    if (!key) {
      return res.status(400).json({
        success: false,
        message: "Debes enviar el key del archivo a eliminar",
      });
    }

    const result = await deleteObjectFromR2(key);

    if (!result.success) {
      return res.status(500).json({
        success: false,
        message: "Error eliminando archivo en Cloudflare R2",
        error: result.error,
      });
    }

    return res.json({
      success: true,
      message: `Archivo eliminado correctamente`,
      key,
    });
  } catch (error) {
    console.error("Error en deleteFileToDrive:", error);
    next(error);
  }
}

