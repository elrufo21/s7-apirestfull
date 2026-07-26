// @ts-nocheck
export const TIPO_DOCUMENTO = [
  { factpro: 1, sunat: "0", descripcion: "DOC.TRIB.NO.DOM.SIN.RUC" },
  { factpro: 2, sunat: "1", descripcion: "Documento Nacional de Identidad" },
  { factpro: 3, sunat: "4", descripcion: "Carnet de extranjeria" },
  { factpro: 4, sunat: "6", descripcion: "Registro Unico de Contribuyentes" },
  { factpro: 5, sunat: "7", descripcion: "Pasaporte" },
];

export const TRIBUTOS = [
  { factpro: 102, sunat: "7152", descripcion: "Impuesto a la bolsa plastica" },
  {
    factpro: 103,
    sunat: "2000",
    descripcion: "ISC Impuesto Selectivo al Consumo",
  },
];

export const AFECTACION_IGV = [
  { factpro: 1, sunat: "10", porcentaje: 18, descripcion: "IGV" },
  { factpro: 20, sunat: "20", porcentaje: 0, descripcion: "Exonerado" },
  {
    factpro: 21,
    sunat: "21",
    porcentaje: 0,
    descripcion: "Exonerado - Transferencia gratuita",
  },
  { factpro: 30, sunat: "30", porcentaje: 0, descripcion: "Inafecto" },
  {
    factpro: 40,
    sunat: "40",
    porcentaje: 0,
    descripcion: "Exportacion de Bienes o Servicios",
  },
  { factpro: 110, sunat: "10", porcentaje: 10, descripcion: "IGV" },
];

export const MONEDAS = [
  { nombre: "Sol Peruano", codigo: "PEN" },
  { nombre: "Dolar", codigo: "USD" },
  { nombre: "Euro", codigo: "EUR" },
];

export const MEDIOS_PAGO = [
  { factpro: 1, fiscal: "1", descripcion: "Deposito en cuenta" },
  { factpro: 2, fiscal: "2", descripcion: "Giro" },
  { factpro: 3, fiscal: "3", descripcion: "Transferencia de fondos" },
  { factpro: 4, fiscal: "4", descripcion: "Orden de pago" },
  { factpro: 5, fiscal: "5", descripcion: "Tarjeta de debito" },
  {
    factpro: 6,
    fiscal: "6",
    descripcion:
      "Tarjeta de credito emitida en el pais por una empresa del sistema financiero",
  },
  {
    factpro: 7,
    fiscal: "7",
    descripcion:
      'Cheques con la clausula de "NO NEGOCIABLE", "INTRANSFERIBLES", "NO A LA ORDEN" u otra equivalente',
  },
  {
    factpro: 8,
    fiscal: "8",
    descripcion:
      "Efectivo, por operaciones en las que no existe obligacion de utilizar medio de pago",
  },
  { factpro: 9, fiscal: "9", descripcion: "Efectivo, en los demas casos" },
  {
    factpro: 10,
    fiscal: "10",
    descripcion: "Medios de pago usados en comercio exterior",
  },
  {
    factpro: 11,
    fiscal: "11",
    descripcion:
      "Documentos emitidos por las EDPYMES y cooperativas no autorizadas a captar depositos",
  },
  {
    factpro: 12,
    fiscal: "12",
    descripcion:
      "Tarjeta de credito emitida en el pais o exterior por empresa no perteneciente al sistema financiero",
  },
  {
    factpro: 13,
    fiscal: "13",
    descripcion:
      "Tarjetas de credito emitidas en el exterior por empresas no domiciliadas",
  },
  {
    factpro: 14,
    fiscal: "101",
    descripcion: "Transferencias - Comercio exterior",
  },
  {
    factpro: 15,
    fiscal: "102",
    descripcion: "Cheques bancarios - Comercio exterior",
  },
  {
    factpro: 16,
    fiscal: "103",
    descripcion: "Orden de pago simple - Comercio exterior",
  },
  {
    factpro: 17,
    fiscal: "104",
    descripcion: "Orden de pago documentario - Comercio exterior",
  },
  {
    factpro: 18,
    fiscal: "105",
    descripcion: "Remesa simple - Comercio exterior",
  },
  {
    factpro: 19,
    fiscal: "106",
    descripcion: "Remesa documentaria - Comercio exterior",
  },
  {
    factpro: 20,
    fiscal: "107",
    descripcion: "Carta de credito simple - Comercio exterior",
  },
  {
    factpro: 21,
    fiscal: "108",
    descripcion: "Carta de credito documentario - Comercio exterior",
  },
  { factpro: 22, fiscal: "999", descripcion: "Otros medios de pago" },
];

export const UNIDADES = [
  { nombre: "Unidad", codigo: "NIU" },
  { nombre: "Servicio", codigo: "ZZ" },
  { nombre: "Kilogramo", codigo: "KGM" },
  { nombre: "Litro", codigo: "LTR" },
  { nombre: "Metro", codigo: "MTR" },
  { nombre: "Metro cuadrado", codigo: "MTK" },
  { nombre: "Metro cubico", codigo: "MTQ" },
  { nombre: "Docena", codigo: "DZN" },
  { nombre: "Caja", codigo: "BX" },
  { nombre: "Bolsa", codigo: "BG" },
  { nombre: "Botella", codigo: "BO" },
  { nombre: "Galon", codigo: "GLL" },
  { nombre: "Libra", codigo: "LBR" },
];

