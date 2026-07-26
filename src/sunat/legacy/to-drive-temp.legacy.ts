// @ts-nocheck
import fs from "fs";
import path from "path";

const TEMP_FOLDER = "./src/toDrive";

export function ensureTempFolder() {
  if (!fs.existsSync(TEMP_FOLDER)) {
    fs.mkdirSync(TEMP_FOLDER);
  }
}

export function saveTempZip(buffer, fileName) {
  ensureTempFolder();

  const filePath = path.join(TEMP_FOLDER, fileName);
  fs.writeFileSync(filePath, buffer);

  return filePath;
}

export function deleteTempFile(filePath) {
  if (fs.existsSync(filePath)) {
    fs.unlinkSync(filePath);
  }
}

