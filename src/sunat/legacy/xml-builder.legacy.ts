// @ts-nocheck
import { create } from "xmlbuilder2";

const DEFAULT_TEMPLATE = {
  cabecera: {
    ublVersionId: "2.1",
    customizationId: "2.0",
    customizationAgencyName: "PE:SUNAT",
    profileId: "0101",
    profileSchemeName: "Tipo de Operacion",
    profileSchemeAgencyName: "PE:SUNAT",
    profileSchemeURI: "urn:pe:gob:sunat:cpe:see:gem:catalogos:catalogo17",
    id: "F001-175",
    issueDate: "2025-11-23",
    issueTime: "11:30:00",
    dueDate: "2025-11-23",
    invoiceTypeCode: "01",
    invoiceTypeCodeAttrs: {
      listAgencyName: "PE:SUNAT",
      listName: "Tipo de Documento",
      listURI: "urn:pe:gob:sunat:cpe:see:gem:catalogos:catalogo01",
      listID: "0101",
      name: "Tipo de Operacion",
    },
    documentCurrencyCode: "PEN",
    documentCurrencyCodeAttrs: {
      listID: "ISO 4217 Alpha",
      listName: "Currency",
      listAgencyName: "United Nations Economic Commission for Europe",
    },
    lineCountNumeric: "4",
  },
  signature: {
    id: "F001-175",
    partyId: "20100100100",
    partyName: "EMPRESA PRUEBA 25",
    uri: "#SignatureSP",
  },
  emisor: {
    ruc: "20100100100",
    nombreComercial: "EMPRESA PRUEBA 25",
    razonSocial: "EMPRESA PRUEBA 25",
    address: {
      ubigeo: "140101",
      addressTypeCode: "0001",
      cityName: "HUANCAYO",
      countrySubentity: "JUNIN",
      district: "HUANCAYO",
      line: "CALLE OCHO DE OCTUBRE 123",
      countryCode: "PE",
    },
    contactName: "",
  },
  cliente: {
    ruc: "20605145648",
    nombreComercial:
      "AGROINVERSIONES Y SERVICIOS AJINOR S.R.L. - AGROSERVIS AJINOR S.R.L.",
    razonSocial:
      "AGROINVERSIONES Y SERVICIOS AJINOR S.R.L. - AGROSERVIS AJINOR S.R.L.",
    address: {
      ubigeo: "",
      cityName: "",
      countrySubentity: "",
      district: "",
      line: "MZA. C LOTE. 46 URB. SAN ISIDRO LA LIBERTAD - TRUJILLO - TRUJILLO",
      countryCode: "",
    },
  },
  paymentTerms: [
    {
      id: "FormaPago",
      paymentMeansId: "Credito",
      amount: "200",
      currencyID: "PEN",
    },
    {
      id: "FormaPago",
      paymentMeansId: "Cuota001",
      amount: "150",
      currencyID: "PEN",
      paymentDueDate: "2025-11-25",
    },
    {
      id: "FormaPago",
      paymentMeansId: "Cuota002",
      amount: "50",
      currencyID: "PEN",
      paymentDueDate: "2025-11-30",
    },
  ],
  taxTotal: {
    taxAmount: "9.43",
    currencyID: "PEN",
    subtotals: [
      {
        taxableAmount: "50.17",
        taxAmount: "9.03",
        currencyID: "PEN",
        taxCategory: {
          id: "S",
          idAttrs: {
            schemeID: "UN/ECE 5305",
            schemeName: "Tax Category Identifier",
            schemeAgencyName: "United Nations Economic Commission for Europe",
          },
          taxScheme: {
            id: "1000",
            idAttrs: { schemeID: "UN/ECE 5153", schemeAgencyID: "6" },
            name: "IGV",
            taxTypeCode: "VAT",
          },
        },
      },
      {
        taxableAmount: "140",
        taxAmount: "0.00",
        currencyID: "PEN",
        taxCategory: {
          id: "E",
          idAttrs: {
            schemeID: "UN/ECE 5305",
            schemeName: "Tax Category Identifier",
            schemeAgencyName: "United Nations Economic Commission for Europe",
          },
          taxScheme: {
            id: "9997",
            idAttrs: { schemeID: "UN/ECE 5153", schemeAgencyID: "6" },
            name: "EXO",
            taxTypeCode: "VAT",
          },
        },
      },
      {
        taxableAmount: "270",
        taxAmount: "0.00",
        currencyID: "PEN",
        taxCategory: {
          id: "O",
          idAttrs: {
            schemeID: "UN/ECE 5305",
            schemeName: "Tax Category Identifier",
            schemeAgencyName: "United Nations Economic Commission for Europe",
          },
          taxScheme: {
            id: "9998",
            idAttrs: { schemeID: "UN/ECE 5153", schemeAgencyID: "6" },
            name: "INA",
            taxTypeCode: "FRE",
          },
        },
      },
      {
        taxAmount: "0.4",
        currencyID: "PEN",
        taxCategory: {
          taxScheme: {
            id: "7152",
            idAttrs: { schemeID: "UN/ECE 5153", schemeAgencyID: "6" },
            name: "ICBPER",
            taxTypeCode: "OTH",
          },
        },
      },
    ],
  },
  legalMonetaryTotal: {
    lineExtensionAmount: "460.17",
    taxInclusiveAmount: "469.6",
    payableAmount: "469.6",
    currencyID: "PEN",
  },
  items: [
    {
      id: "1",
      quantity: "1",
      unitCode: "NIU",
      unitCodeListID: "UN/ECE rec 20",
      unitCodeListAgencyName: "United Nations Economic Commission for Europe",
      lineExtensionAmount: "50",
      currencyID: "PEN",
      pricingReference: {
        priceAmount: "59",
        currencyID: "PEN",
        priceTypeCode: "01",
        priceTypeCodeAttrs: {
          listName: "Tipo de Precio",
          listAgencyName: "PE:SUNAT",
          listURI: "urn:pe:gob:sunat:cpe:see:gem:catalogos:catalogo16",
        },
      },
      taxTotal: {
        taxAmount: "9",
        currencyID: "PEN",
        subtotals: [
          {
            taxableAmount: "50",
            taxAmount: "9",
            currencyID: "PEN",
            taxCategory: {
              id: "S",
              idAttrs: {
                schemeID: "UN/ECE 5305",
                schemeName: "Tax Category Identifier",
                schemeAgencyName:
                  "United Nations Economic Commission for Europe",
              },
              percent: "18",
              taxExemptionReasonCode: "10",
              taxExemptionReasonCodeAttrs: {
                listAgencyName: "PE:SUNAT",
                listName: "Afectacion del IGV",
                listURI: "urn:pe:gob:sunat:cpe:see:gem:catalogos:catalogo07",
              },
              taxScheme: {
                id: "1000",
                idAttrs: {
                  schemeID: "UN/ECE 5153",
                  schemeName: "Codigo de tributos",
                  schemeAgencyName: "PE:SUNAT",
                },
                name: "IGV",
                taxTypeCode: "VAT",
              },
            },
          },
        ],
      },
      item: {
        description: "MOCHILA",
        sellersItemId: "195",
        classificationCode: "10191509",
        classificationAttrs: {
          listID: "UNSPSC",
          listAgencyName: "GS1 US",
          listName: "Item Classification",
        },
      },
      price: {
        amount: "50",
        currencyID: "PEN",
      },
    },
    {
      id: "2",
      quantity: "2",
      unitCode: "NIU",
      unitCodeListID: "UN/ECE rec 20",
      unitCodeListAgencyName: "United Nations Economic Commission for Europe",
      lineExtensionAmount: "140",
      currencyID: "PEN",
      pricingReference: {
        priceAmount: "70",
        currencyID: "PEN",
        priceTypeCode: "01",
        priceTypeCodeAttrs: {
          listName: "Tipo de Precio",
          listAgencyName: "PE:SUNAT",
          listURI: "urn:pe:gob:sunat:cpe:see:gem:catalogos:catalogo16",
        },
      },
      taxTotal: {
        taxAmount: "0",
        currencyID: "PEN",
        subtotals: [
          {
            taxableAmount: "140",
            taxAmount: "0",
            currencyID: "PEN",
            taxCategory: {
              id: "E",
              idAttrs: {
                schemeID: "UN/ECE 5305",
                schemeName: "Tax Category Identifier",
                schemeAgencyName:
                  "United Nations Economic Commission for Europe",
              },
              percent: "18",
              taxExemptionReasonCode: "20",
              taxExemptionReasonCodeAttrs: {
                listAgencyName: "PE:SUNAT",
                listName: "Afectacion del IGV",
                listURI: "urn:pe:gob:sunat:cpe:see:gem:catalogos:catalogo07",
              },
              taxScheme: {
                id: "9997",
                idAttrs: {
                  schemeID: "UN/ECE 5153",
                  schemeName: "Codigo de tributos",
                  schemeAgencyName: "PE:SUNAT",
                },
                name: "EXO",
                taxTypeCode: "VAT",
              },
            },
          },
        ],
      },
      item: {
        description: "LIBRO COQUITO",
        sellersItemId: "195",
        classificationCode: "10191509",
        classificationAttrs: {
          listID: "UNSPSC",
          listAgencyName: "GS1 US",
          listName: "Item Classification",
        },
      },
      price: {
        amount: "70",
        currencyID: "PEN",
      },
    },
    {
      id: "3",
      quantity: "3",
      unitCode: "NIU",
      unitCodeListID: "UN/ECE rec 20",
      unitCodeListAgencyName: "United Nations Economic Commission for Europe",
      lineExtensionAmount: "270",
      currencyID: "PEN",
      pricingReference: {
        priceAmount: "90",
        currencyID: "PEN",
        priceTypeCode: "01",
        priceTypeCodeAttrs: {
          listName: "Tipo de Precio",
          listAgencyName: "PE:SUNAT",
          listURI: "urn:pe:gob:sunat:cpe:see:gem:catalogos:catalogo16",
        },
      },
      taxTotal: {
        taxAmount: "0",
        currencyID: "PEN",
        subtotals: [
          {
            taxableAmount: "270",
            taxAmount: "0",
            currencyID: "PEN",
            taxCategory: {
              id: "O",
              idAttrs: {
                schemeID: "UN/ECE 5305",
                schemeName: "Tax Category Identifier",
                schemeAgencyName:
                  "United Nations Economic Commission for Europe",
              },
              percent: "18",
              taxExemptionReasonCode: "30",
              taxExemptionReasonCodeAttrs: {
                listAgencyName: "PE:SUNAT",
                listName: "Afectacion del IGV",
                listURI: "urn:pe:gob:sunat:cpe:see:gem:catalogos:catalogo07",
              },
              taxScheme: {
                id: "9998",
                idAttrs: {
                  schemeID: "UN/ECE 5153",
                  schemeName: "Codigo de tributos",
                  schemeAgencyName: "PE:SUNAT",
                },
                name: "INA",
                taxTypeCode: "FRE",
              },
            },
          },
        ],
      },
      item: {
        description: "MANZANA",
        sellersItemId: "195",
        classificationCode: "10191509",
        classificationAttrs: {
          listID: "UNSPSC",
          listAgencyName: "GS1 US",
          listName: "Item Classification",
        },
      },
      price: {
        amount: "90",
        currencyID: "PEN",
      },
    },
    {
      id: "4",
      quantity: "1",
      unitCode: "NIU",
      unitCodeListID: "UN/ECE rec 20",
      unitCodeListAgencyName: "United Nations Economic Commission for Europe",
      lineExtensionAmount: "0.17",
      currencyID: "PEN",
      pricingReference: {
        priceAmount: "0.6",
        currencyID: "PEN",
        priceTypeCode: "01",
        priceTypeCodeAttrs: {
          listName: "Tipo de Precio",
          listAgencyName: "PE:SUNAT",
          listURI: "urn:pe:gob:sunat:cpe:see:gem:catalogos:catalogo16",
        },
      },
      taxTotal: {
        taxAmount: "0.43",
        currencyID: "PEN",
        subtotals: [
          {
            taxableAmount: "0.17",
            taxAmount: "0.03",
            currencyID: "PEN",
            taxCategory: {
              id: "S",
              idAttrs: {
                schemeID: "UN/ECE 5305",
                schemeName: "Tax Category Identifier",
                schemeAgencyName:
                  "United Nations Economic Commission for Europe",
              },
              percent: "18",
              taxExemptionReasonCode: "10",
              taxExemptionReasonCodeAttrs: {
                listAgencyName: "PE:SUNAT",
                listName: "Afectacion del IGV",
                listURI: "urn:pe:gob:sunat:cpe:see:gem:catalogos:catalogo07",
              },
              taxScheme: {
                id: "1000",
                idAttrs: {
                  schemeID: "UN/ECE 5153",
                  schemeName: "Codigo de tributos",
                  schemeAgencyName: "PE:SUNAT",
                },
                name: "IGV",
                taxTypeCode: "VAT",
              },
            },
          },
          {
            taxAmount: "0.4",
            currencyID: "PEN",
            baseUnitMeasure: "1",
            baseUnitMeasureAttrs: { unitCode: "NIU" },
            taxCategory: {
              perUnitAmount: "0.4",
              perUnitAmountAttrs: { currencyID: "PEN" },
              taxScheme: {
                id: "7152",
                name: "ICBPER",
                taxTypeCode: "OTH",
              },
            },
          },
        ],
      },
      item: {
        description: "BOLSA PLÁSTICA",
        sellersItemId: "195",
        classificationCode: "10191509",
        classificationAttrs: {
          listID: "UNSPSC",
          listAgencyName: "GS1 US",
          listName: "Item Classification",
        },
      },
      price: {
        amount: "0.17",
        currencyID: "PEN",
      },
    },
  ],
};

const BOLETA_TEMPLATE_OVERRIDES = {
  cabecera: {
    id: "B001-175",
    invoiceTypeCode: "03",
  },
  signature: {
    id: "B001-175",
  },
};

const NOTA_CREDITO_TEMPLATE_OVERRIDES = {
  cabecera: {
    id: "FC01-1",
    creditNoteTypeCode: "07",
    creditNoteTypeCodeAttrs: {
      listAgencyName: "PE:SUNAT",
      listName: "Tipo de Documento",
      listURI: "urn:pe:gob:sunat:cpe:see:gem:catalogos:catalogo01",
      name: "Tipo de Nota de Credito",
    },
  },
  signature: {
    id: "FC01-1",
  },
  references: {
    discrepancyResponse: {
      referenceId: "F001-175",
      responseCode: "01",
      description: "ANULACION DE LA OPERACION",
    },
    billingReference: {
      id: "F001-175",
      documentTypeCode: "01",
    },
  },
};

const NOTA_DEBITO_TEMPLATE_OVERRIDES = {
  cabecera: {
    id: "FD01-1",
    debitNoteTypeCode: "08",
    debitNoteTypeCodeAttrs: {
      listAgencyName: "PE:SUNAT",
      listName: "Tipo de Documento",
      listURI: "urn:pe:gob:sunat:cpe:see:gem:catalogos:catalogo01",
      name: "Tipo de Nota de Debito",
    },
  },
  signature: {
    id: "FD01-1",
  },
  references: {
    discrepancyResponse: {
      referenceId: "F001-175",
      responseCode: "01",
      description: "INTERESES POR MORA",
    },
    billingReference: {
      id: "F001-175",
      documentTypeCode: "01",
    },
  },
};

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function deepMerge(base, override) {
  if (Array.isArray(base)) {
    return Array.isArray(override) ? override : base;
  }

  if (!isObject(base)) {
    return override !== undefined ? override : base;
  }

  const merged = { ...base };
  if (!isObject(override)) {
    return merged;
  }

  for (const key of Object.keys(override)) {
    const baseValue = base[key];
    const overrideValue = override[key];

    if (Array.isArray(baseValue)) {
      merged[key] = Array.isArray(overrideValue) ? overrideValue : baseValue;
      continue;
    }

    if (isObject(baseValue)) {
      merged[key] = deepMerge(baseValue, overrideValue);
      continue;
    }

    merged[key] = overrideValue;
  }

  return merged;
}

function txt(node, name, value, attrs) {
  const child = attrs ? node.ele(name, attrs) : node.ele(name);
  if (value !== undefined && value !== null && value !== "") {
    child.txt(String(value));
  }
  return child;
}

function cdata(node, name, value, attrs) {
  const child = attrs ? node.ele(name, attrs) : node.ele(name);
  if (value !== undefined && value !== null && value !== "") {
    child.dat(String(value));
  }
  return child;
}

function appendParty(parent, party, includeAddressTypeCode = false) {
  const partyNode = parent.ele("cac:Party");
  const documentTypeCode = String(party?.documentTypeCode || "6");

  txt(partyNode.ele("cac:PartyIdentification"), "cbc:ID", party.ruc, {
    schemeID: documentTypeCode,
    schemeName: "Documento de Identidad",
    schemeAgencyName: "PE:SUNAT",
    schemeURI: "urn:pe:gob:sunat:cpe:see:gem:catalogos:catalogo06",
  });

  cdata(partyNode.ele("cac:PartyName"), "cbc:Name", party.nombreComercial);

  const taxScheme = partyNode.ele("cac:PartyTaxScheme");
  cdata(taxScheme, "cbc:RegistrationName", party.razonSocial);
  txt(taxScheme, "cbc:CompanyID", party.ruc, {
    schemeID: documentTypeCode,
    schemeName: "SUNAT:Identificador de Documento de Identidad",
    schemeAgencyName: "PE:SUNAT",
    schemeURI: "urn:pe:gob:sunat:cpe:see:gem:catalogos:catalogo06",
  });

  txt(taxScheme.ele("cac:TaxScheme"), "cbc:ID", party.ruc, {
    schemeID: documentTypeCode,
    schemeName: "SUNAT:Identificador de Documento de Identidad",
    schemeAgencyName: "PE:SUNAT",
    schemeURI: "urn:pe:gob:sunat:cpe:see:gem:catalogos:catalogo06",
  });

  const legal = partyNode.ele("cac:PartyLegalEntity");
  cdata(legal, "cbc:RegistrationName", party.razonSocial);

  const address = legal.ele("cac:RegistrationAddress");
  txt(address, "cbc:ID", party.address?.ubigeo, {
    schemeName: "Ubigeos",
    schemeAgencyName: "PE:INEI",
  });

  if (includeAddressTypeCode) {
    txt(address, "cbc:AddressTypeCode", party.address?.addressTypeCode, {
      listAgencyName: "PE:SUNAT",
      listName: "Establecimientos anexos",
    });
  }

  cdata(address, "cbc:CityName", party.address?.cityName);
  cdata(address, "cbc:CountrySubentity", party.address?.countrySubentity);
  cdata(address, "cbc:District", party.address?.district);
  cdata(address.ele("cac:AddressLine"), "cbc:Line", party.address?.line);
  txt(
    address.ele("cac:Country"),
    "cbc:IdentificationCode",
    party.address?.countryCode,
    {
      listID: "ISO 3166-1",
      listAgencyName: "United Nations Economic Commission for Europe",
      listName: "Country",
    },
  );

  if (Object.prototype.hasOwnProperty.call(party, "contactName")) {
    cdata(partyNode.ele("cac:Contact"), "cbc:Name", party.contactName);
  }

  return partyNode;
}

function appendTaxTotal(parent, taxTotal) {
  if (!taxTotal) {
    return;
  }

  const taxTotalNode = parent.ele("cac:TaxTotal");
  txt(taxTotalNode, "cbc:TaxAmount", taxTotal.taxAmount, {
    currencyID: taxTotal.currencyID || "PEN",
  });

  for (const subtotal of taxTotal.subtotals || []) {
    const subtotalNode = taxTotalNode.ele("cac:TaxSubtotal");

    if (subtotal.taxableAmount !== undefined) {
      txt(subtotalNode, "cbc:TaxableAmount", subtotal.taxableAmount, {
        currencyID: subtotal.currencyID || "PEN",
      });
    }

    txt(subtotalNode, "cbc:TaxAmount", subtotal.taxAmount, {
      currencyID: subtotal.currencyID || "PEN",
    });

    if (subtotal.baseUnitMeasure !== undefined) {
      txt(
        subtotalNode,
        "cbc:BaseUnitMeasure",
        subtotal.baseUnitMeasure,
        subtotal.baseUnitMeasureAttrs || { unitCode: "NIU" },
      );
    }

    const category = subtotalNode.ele("cac:TaxCategory");
    if (subtotal.taxCategory?.id !== undefined) {
      txt(
        category,
        "cbc:ID",
        subtotal.taxCategory.id,
        subtotal.taxCategory.idAttrs,
      );
    }

    if (subtotal.taxCategory?.percent !== undefined) {
      txt(category, "cbc:Percent", subtotal.taxCategory.percent);
    }

    if (subtotal.taxCategory?.taxExemptionReasonCode !== undefined) {
      txt(
        category,
        "cbc:TaxExemptionReasonCode",
        subtotal.taxCategory.taxExemptionReasonCode,
        subtotal.taxCategory.taxExemptionReasonCodeAttrs,
      );
    }

    if (subtotal.taxCategory?.perUnitAmount !== undefined) {
      txt(
        category,
        "cbc:PerUnitAmount",
        subtotal.taxCategory.perUnitAmount,
        subtotal.taxCategory.perUnitAmountAttrs,
      );
    }

    const scheme = category.ele("cac:TaxScheme");
    txt(
      scheme,
      "cbc:ID",
      subtotal.taxCategory?.taxScheme?.id,
      subtotal.taxCategory?.taxScheme?.idAttrs,
    );
    txt(scheme, "cbc:Name", subtotal.taxCategory?.taxScheme?.name);
    txt(
      scheme,
      "cbc:TaxTypeCode",
      subtotal.taxCategory?.taxScheme?.taxTypeCode,
    );
  }
}

function appendDocumentLine(
  parent,
  item,
  { lineTag = "cac:InvoiceLine", quantityTag = "cbc:InvoicedQuantity" } = {},
) {
  const line = parent.ele(lineTag);
  txt(line, "cbc:ID", item.id);
  txt(line, quantityTag, item.quantity, {
    unitCode: item.unitCode,
  });
  txt(line, "cbc:LineExtensionAmount", item.lineExtensionAmount, {
    currencyID: item.currencyID || "PEN",
  });

  if (item.pricingReference) {
    const ref = line
      .ele("cac:PricingReference")
      .ele("cac:AlternativeConditionPrice");
    txt(ref, "cbc:PriceAmount", item.pricingReference?.priceAmount, {
      currencyID: item.pricingReference?.currencyID || item.currencyID || "PEN",
    });
    txt(
      ref,
      "cbc:PriceTypeCode",
      item.pricingReference?.priceTypeCode,
      item.pricingReference?.priceTypeCodeAttrs,
    );
  }

  appendTaxTotal(line, item.taxTotal);

  const itemNode = line.ele("cac:Item");
  cdata(itemNode, "cbc:Description", item.item?.description);
  cdata(
    itemNode.ele("cac:SellersItemIdentification"),
    "cbc:ID",
    item.item?.sellersItemId,
  );
  txt(
    itemNode.ele("cac:CommodityClassification"),
    "cbc:ItemClassificationCode",
    item.item?.classificationCode,
    item.item?.classificationAttrs,
  );

  txt(line.ele("cac:Price"), "cbc:PriceAmount", item.price?.amount, {
    currencyID: item.price?.currencyID || item.currencyID || "PEN",
  });
}

function appendInvoiceLine(parent, item) {
  appendDocumentLine(parent, item, {
    lineTag: "cac:InvoiceLine",
    quantityTag: "cbc:InvoicedQuantity",
  });
}

function appendCreditNoteLine(parent, item) {
  appendDocumentLine(parent, item, {
    lineTag: "cac:CreditNoteLine",
    quantityTag: "cbc:CreditedQuantity",
  });
}

function appendDebitNoteLine(parent, item) {
  appendDocumentLine(parent, item, {
    lineTag: "cac:DebitNoteLine",
    quantityTag: "cbc:DebitedQuantity",
  });
}

function createRootNode(doc, rootName, defaultNamespace) {
  return doc.ele(rootName, {
    "xmlns:xsi": "http://www.w3.org/2001/XMLSchema-instance",
    "xmlns:xsd": "http://www.w3.org/2001/XMLSchema",
    "xmlns:cac":
      "urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2",
    "xmlns:cbc":
      "urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2",
    "xmlns:ccts": "urn:un:unece:uncefact:documentation:2",
    "xmlns:ds": "http://www.w3.org/2000/09/xmldsig#",
    "xmlns:ext":
      "urn:oasis:names:specification:ubl:schema:xsd:CommonExtensionComponents-2",
    "xmlns:qdt":
      "urn:oasis:names:specification:ubl:schema:xsd:QualifiedDatatypes-2",
    "xmlns:udt":
      "urn:un:unece:uncefact:data:specification:UnqualifiedDataTypesSchemaModule:2",
    xmlns: defaultNamespace,
  });
}

function appendUblExtension(root) {
  root
    .ele("ext:UBLExtensions")
    .ele("ext:UBLExtension")
    .ele("ext:ExtensionContent")
    .up()
    .up()
    .up();
}

function appendSignature(root, signature) {
  const signatureNode = root.ele("cac:Signature");
  txt(signatureNode, "cbc:ID", signature.id);
  const signatoryParty = signatureNode.ele("cac:SignatoryParty");
  txt(
    signatoryParty.ele("cac:PartyIdentification"),
    "cbc:ID",
    signature.partyId,
  );
  cdata(signatoryParty.ele("cac:PartyName"), "cbc:Name", signature.partyName);
  txt(
    signatureNode
      .ele("cac:DigitalSignatureAttachment")
      .ele("cac:ExternalReference"),
    "cbc:URI",
    signature.uri,
  );
}

function appendReferences(root, references = {}) {
  const discrepancyResponse =
    references.discrepancyResponse || references.discrepancy;
  if (discrepancyResponse) {
    const node = root.ele("cac:DiscrepancyResponse");
    txt(node, "cbc:ReferenceID", discrepancyResponse.referenceId);
    txt(node, "cbc:ResponseCode", discrepancyResponse.responseCode);
    cdata(node, "cbc:Description", discrepancyResponse.description);
  }

  const billingRef = references.billingReference || references.documentReference;
  const billingRefs = Array.isArray(billingRef)
    ? billingRef
    : billingRef
      ? [billingRef]
      : [];

  for (const reference of billingRefs) {
    const node = root
      .ele("cac:BillingReference")
      .ele("cac:InvoiceDocumentReference");
    txt(node, "cbc:ID", reference.id);
    txt(node, "cbc:DocumentTypeCode", reference.documentTypeCode);
  }
}

function appendCommonParties(root, data) {
  appendSignature(root, data.signature);
  appendParty(root.ele("cac:AccountingSupplierParty"), data.emisor, true);
  appendParty(root.ele("cac:AccountingCustomerParty"), data.cliente, false);
}

export function getFacturaTemplateData() {
  return structuredClone(DEFAULT_TEMPLATE);
}

export function getBoletaTemplateData() {
  return deepMerge(getFacturaTemplateData(), BOLETA_TEMPLATE_OVERRIDES);
}

export function getNotaCreditoTemplateData() {
  return deepMerge(getFacturaTemplateData(), NOTA_CREDITO_TEMPLATE_OVERRIDES);
}

export function getNotaDebitoTemplateData() {
  return deepMerge(getFacturaTemplateData(), NOTA_DEBITO_TEMPLATE_OVERRIDES);
}

function buildComprobanteXML(baseTemplate, overrides = {}) {
  const data = deepMerge(baseTemplate, overrides);

  const doc = create({ version: "1.0", encoding: "utf-8" });
  const root = createRootNode(
    doc,
    "Invoice",
    "urn:oasis:names:specification:ubl:schema:xsd:Invoice-2",
  );

  appendUblExtension(root);

  txt(root, "cbc:UBLVersionID", data.cabecera.ublVersionId);
  txt(root, "cbc:CustomizationID", data.cabecera.customizationId, {
    schemeAgencyName: data.cabecera.customizationAgencyName,
  });
  txt(root, "cbc:ProfileID", data.cabecera.profileId, {
    schemeName: data.cabecera.profileSchemeName,
    schemeAgencyName: data.cabecera.profileSchemeAgencyName,
    schemeURI: data.cabecera.profileSchemeURI,
  });
  txt(root, "cbc:ID", data.cabecera.id);
  txt(root, "cbc:IssueDate", data.cabecera.issueDate);
  txt(root, "cbc:IssueTime", data.cabecera.issueTime);
  txt(
    root,
    "cbc:InvoiceTypeCode",
    data.cabecera.invoiceTypeCode,
    data.cabecera.invoiceTypeCodeAttrs,
  );
  txt(
    root,
    "cbc:DocumentCurrencyCode",
    data.cabecera.documentCurrencyCode,
    data.cabecera.documentCurrencyCodeAttrs,
  );
  txt(root, "cbc:LineCountNumeric", data.cabecera.lineCountNumeric);

  appendCommonParties(root, data);

  for (const term of data.paymentTerms || []) {
    const node = root.ele("cac:PaymentTerms");
    txt(node, "cbc:ID", term.id);
    txt(node, "cbc:PaymentMeansID", term.paymentMeansId);
    if (term.amount !== undefined && term.amount !== null && term.amount !== "") {
      txt(node, "cbc:Amount", term.amount, {
        currencyID: term.currencyID || "PEN",
      });
    }
    if (term.paymentDueDate !== undefined) {
      txt(node, "cbc:PaymentDueDate", term.paymentDueDate);
    }
  }

  appendTaxTotal(root, data.taxTotal);

  const legal = root.ele("cac:LegalMonetaryTotal");
  txt(
    legal,
    "cbc:LineExtensionAmount",
    data.legalMonetaryTotal.lineExtensionAmount,
    {
      currencyID: data.legalMonetaryTotal.currencyID || "PEN",
    },
  );
  txt(
    legal,
    "cbc:TaxInclusiveAmount",
    data.legalMonetaryTotal.taxInclusiveAmount,
    {
      currencyID: data.legalMonetaryTotal.currencyID || "PEN",
    },
  );
  txt(legal, "cbc:PayableAmount", data.legalMonetaryTotal.payableAmount, {
    currencyID: data.legalMonetaryTotal.currencyID || "PEN",
  });

  for (const item of data.items || []) {
    appendInvoiceLine(root, item);
  }

  return root.end({ prettyPrint: true, indent: "    " });
}

function buildCreditNoteXMLInternal(baseTemplate, overrides = {}) {
  const data = deepMerge(baseTemplate, overrides);

  const doc = create({ version: "1.0", encoding: "utf-8" });
  const root = createRootNode(
    doc,
    "CreditNote",
    "urn:oasis:names:specification:ubl:schema:xsd:CreditNote-2",
  );

  appendUblExtension(root);

  txt(root, "cbc:UBLVersionID", data.cabecera.ublVersionId);
  txt(root, "cbc:CustomizationID", data.cabecera.customizationId, {
    schemeAgencyName: data.cabecera.customizationAgencyName,
  });
  txt(root, "cbc:ID", data.cabecera.id);
  txt(root, "cbc:IssueDate", data.cabecera.issueDate);
  txt(root, "cbc:IssueTime", data.cabecera.issueTime);
  txt(
    root,
    "cbc:CreditNoteTypeCode",
    data.cabecera.creditNoteTypeCode,
    data.cabecera.creditNoteTypeCodeAttrs,
  );
  txt(
    root,
    "cbc:DocumentCurrencyCode",
    data.cabecera.documentCurrencyCode,
    data.cabecera.documentCurrencyCodeAttrs,
  );

  appendReferences(root, data.references || data.referencia || {});
  appendCommonParties(root, data);
  appendTaxTotal(root, data.taxTotal);

  const legal = root.ele("cac:LegalMonetaryTotal");
  txt(legal, "cbc:PayableAmount", data.legalMonetaryTotal.payableAmount, {
    currencyID: data.legalMonetaryTotal.currencyID || "PEN",
  });

  for (const item of data.items || []) {
    appendCreditNoteLine(root, item);
  }

  return root.end({ prettyPrint: true, indent: "    " });
}

function buildDebitNoteXMLInternal(baseTemplate, overrides = {}) {
  const data = deepMerge(baseTemplate, overrides);

  const doc = create({ version: "1.0", encoding: "utf-8" });
  const root = createRootNode(
    doc,
    "DebitNote",
    "urn:oasis:names:specification:ubl:schema:xsd:DebitNote-2",
  );

  appendUblExtension(root);

  txt(root, "cbc:UBLVersionID", data.cabecera.ublVersionId);
  txt(root, "cbc:CustomizationID", data.cabecera.customizationId, {
    schemeAgencyName: data.cabecera.customizationAgencyName,
  });
  txt(root, "cbc:ID", data.cabecera.id);
  txt(root, "cbc:IssueDate", data.cabecera.issueDate);
  txt(root, "cbc:IssueTime", data.cabecera.issueTime);
  txt(
    root,
    "cbc:DebitNoteTypeCode",
    data.cabecera.debitNoteTypeCode,
    data.cabecera.debitNoteTypeCodeAttrs,
  );
  txt(
    root,
    "cbc:DocumentCurrencyCode",
    data.cabecera.documentCurrencyCode,
    data.cabecera.documentCurrencyCodeAttrs,
  );

  appendReferences(root, data.references || data.referencia || {});
  appendCommonParties(root, data);
  appendTaxTotal(root, data.taxTotal);

  const requested = root.ele("cac:RequestedMonetaryTotal");
  txt(requested, "cbc:PayableAmount", data.legalMonetaryTotal.payableAmount, {
    currencyID: data.legalMonetaryTotal.currencyID || "PEN",
  });

  for (const item of data.items || []) {
    appendDebitNoteLine(root, item);
  }

  return root.end({ prettyPrint: true, indent: "    " });
}

export function buildInvoiceXML(overrides = {}) {
  return buildComprobanteXML(getFacturaTemplateData(), overrides);
}

export function buildBoletaXML(overrides = {}) {
  return buildComprobanteXML(getBoletaTemplateData(), overrides);
}

export function buildCreditNoteXML(overrides = {}) {
  return buildCreditNoteXMLInternal(getNotaCreditoTemplateData(), overrides);
}

export function buildDebitNoteXML(overrides = {}) {
  return buildDebitNoteXMLInternal(getNotaDebitoTemplateData(), overrides);
}

