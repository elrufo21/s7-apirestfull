// @ts-nocheck
import axios from "axios";
import { XMLParser } from "fast-xml-parser";

const SOAP_ENDPOINT =
  "https://e-beta.sunat.gob.pe/ol-ti-itcpfegem-beta/billService";

const parser = new XMLParser({
  ignoreAttributes: false,
  removeNSPrefix: true,
});

function parseSoapBody(xmlLike) {
  if (!xmlLike || typeof xmlLike !== "string") {
    return null;
  }

  try {
    const parsed = parser.parse(xmlLike);
    return parsed?.Envelope?.Body || null;
  } catch {
    return null;
  }
}

function buildSunatFaultError({ body, status, statusText, soapBody }) {
  const { faultcode, faultstring } = body?.Fault || {};
  const rawFaultcode = faultcode || "SIN_CODIGO";
  const rawFaultstring = faultstring || "SIN_DESCRIPCION";

  const codeMatch =
    /Client[.:]?\s*(\d+)/i.exec(rawFaultcode) ||
    /Client\s*-\s*(\d+)/i.exec(rawFaultcode);
  const parsedCode = codeMatch?.[1] || "SIN_CODIGO";

  const error = new Error(
    `SUNAT devolvio un error: ${rawFaultcode} - ${rawFaultstring}`,
  );
  error.sunatCode = parsedCode;
  error.sentSoap = soapBody;
  error.details = {
    sunatCode: parsedCode,
    faultcode: rawFaultcode,
    faultstring: rawFaultstring,
    httpStatus: status,
    httpStatusText: statusText,
  };
  return error;
}

function buildSoapEnvelope(nombreZip, zipBase64) {
  return `
    <soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/"
        xmlns:ser="http://service.sunat.gob.pe">
      <soapenv:Header/>
      <soapenv:Body>
        <ser:sendBill>
          <fileName>${nombreZip}.zip</fileName>
          <contentFile>${zipBase64}</contentFile>
        </ser:sendBill>
      </soapenv:Body>
    </soapenv:Envelope>
  `;
}

export async function sendToSunat(zipBase64, nombreZip, emisor) {
  if (!zipBase64) {
    throw new Error("Falta el contenido del ZIP en base64");
  }

  if (!nombreZip) {
    throw new Error("Falta el nombre del ZIP a enviar");
  }

  if (!emisor?.usuario_emisor || !emisor?.clave_emisor) {
    throw new Error("Faltan las credenciales de SUNAT");
  }

  const soapBody = buildSoapEnvelope(nombreZip, zipBase64);

  let data;
  let status;
  let statusText;

  try {
    ({ data, status, statusText } = await axios.post(SOAP_ENDPOINT, soapBody, {
      headers: {
        "Content-Type": "text/xml",
        Authorization:
          "Basic " +
          Buffer.from(
            `${emisor.usuario_emisor}:${emisor.clave_emisor}`
          ).toString("base64"),
      },
      validateStatus: () => true,
    }));
  } catch (err) {
    const responseData =
      typeof err?.response?.data === "string"
        ? err.response.data
        : String(err?.response?.data || "");
    const parsedBody = parseSoapBody(responseData);

    if (parsedBody?.Fault) {
      throw buildSunatFaultError({
        body: parsedBody,
        status: err?.response?.status,
        statusText: err?.response?.statusText,
        soapBody,
      });
    }

    const error = new Error(`No se pudo enviar a SUNAT: ${err.message}`);
    error.sentSoap = soapBody;
    if (err?.response?.status) {
      error.details = {
        httpStatus: err.response.status,
        httpStatusText: err.response.statusText,
        responseSnippet: responseData.slice(0, 2000),
      };
    }
    throw error;
  }

  const body = parseSoapBody(
    typeof data === "string" ? data : String(data || ""),
  );

  if (!body) {
    const error = new Error("Respuesta de SUNAT invalida");
    error.sentSoap = soapBody;
    error.details = {
      httpStatus: status,
      httpStatusText: statusText,
      responseSnippet: String(data || "").slice(0, 2000),
    };
    throw error;
  }

  if (body.Fault) {
    throw buildSunatFaultError({ body, status, statusText, soapBody });
  }

  if (Number(status) >= 400) {
    const error = new Error(
      `SUNAT devolvio HTTP ${status}${statusText ? ` ${statusText}` : ""}`,
    );
    error.sentSoap = soapBody;
    error.details = {
      httpStatus: status,
      httpStatusText: statusText,
      responseSnippet: String(data || "").slice(0, 2000),
    };
    throw error;
  }

  const cdrBase64 = body.sendBillResponse?.applicationResponse;
  if (!cdrBase64) {
    const error = new Error("SUNAT no devolvio el CDR esperado");
    error.sentSoap = soapBody;
    throw error;
  }

  return cdrBase64;
}

