// @ts-nocheck
import AdmZip from "adm-zip";
import fs from "fs";
import path from "path";
import { XMLParser } from "fast-xml-parser";

const OUTPUT_DIR = path.join(process.cwd(), "response");
const parser = new XMLParser({ ignoreAttributes: false });

export function unzipCDR(base64, ruc, serie, numero) {
  if (!base64) {
    return { success: false, message: "No se recibio el CDR en base64" };
  }

  fs.mkdirSync(OUTPUT_DIR, { recursive: true });

  const safeRuc = ruc || "cdr";
  const safeSerie = serie || "serie";
  const safeNumero = numero || "00000000";

  const zipFileName = `R-${safeRuc}-${safeSerie}-${safeNumero}.zip`;
  const zipPath = path.join(OUTPUT_DIR, zipFileName);

  const zipBuffer = Buffer.from(base64, "base64");
  fs.writeFileSync(zipPath, zipBuffer);

  const zip = new AdmZip(zipPath);
  zip.extractAllTo(OUTPUT_DIR, true);

  const cdrEntry = zip.getEntries().find((entry) => entry.entryName.endsWith(".xml"));

  if (!cdrEntry) {
    return { success: false, message: "El CDR no contiene un XML" };
  }

  const xmlContent = cdrEntry.getData().toString("utf8");
  const json = parser.parse(xmlContent);

  const appResponse = json["ar:ApplicationResponse"] || json.ApplicationResponse;

  if (!appResponse) {
    return {
      success: false,
      message: "No se encontro ApplicationResponse en el CDR",
    };
  }

  const docResponse = appResponse["cac:DocumentResponse"] || {};
  const response = docResponse["cac:Response"] || {};

  const responseCode = response["cbc:ResponseCode"];
  const description = response["cbc:Description"];

  return {
    success: true,
    savedZip: zipPath,
    xmlFile: cdrEntry.entryName,
    xmlContent,
    responseCode,
    description,
    date: new Date().toISOString(),
  };
}

