// @ts-nocheck
import fs from "fs";
import path from "path";
import AdmZip from "adm-zip";

const ZIP_FOLDER = path.join(process.cwd(), "zip");

export function makeZip(filename, xml) {
  const zip = new AdmZip();
  zip.addFile(`${filename}.xml`, Buffer.from(xml, "utf8"));

  fs.mkdirSync(ZIP_FOLDER, { recursive: true });

  const zipPath = path.join(ZIP_FOLDER, `${filename}.zip`);
  zip.writeZip(zipPath);
  console.log("ZIP guardado en:", zipPath);

  return zip.toBuffer();
}

