#include "HBXML.h"
#include <libxml/parser.h>
#include <libxml/parserInternals.h>

static void HBXMLSilent(void *context, const char *message, ...) {
    (void)context; (void)message;
}
static void HBXMLRejectSubset(void *context, const xmlChar *name, const xmlChar *externalID, const xmlChar *systemID) {
    xmlParserCtxtPtr parser = (xmlParserCtxtPtr)context;
    (void)name; (void)externalID; (void)systemID;
    xmlStopParser(parser); parser->wellFormed = 0;
}
static xmlParserInputPtr HBXMLRejectExternal(void *context, const xmlChar *publicID, const xmlChar *systemID) {
    HBXMLRejectSubset(context, NULL, publicID, systemID); return NULL;
}
static xmlEntityPtr HBXMLRejectParameter(void *context, const xmlChar *name) {
    HBXMLRejectSubset(context, name, NULL, NULL); return NULL;
}
xmlDocPtr HBXMLDocument(const char *bytes, unsigned long length) {
    xmlParserCtxtPtr parser;
    xmlDocPtr document;
    int result, valid;
    if (!bytes || !length || length > 8UL * 1024 * 1024) return NULL;
    parser = xmlCreateMemoryParserCtxt(bytes, (int)length);
    if (!parser) return NULL;
    if (!parser->sax || (void *)parser->sax == (void *)&xmlDefaultSAXHandler) { xmlFreeParserCtxt(parser); return NULL; }
    /* Keep the runtime-owned table: old SDKs omit its SAX2 trailing fields. */
    parser->sax->internalSubset = HBXMLRejectSubset;
    parser->sax->externalSubset = HBXMLRejectSubset;
    parser->sax->resolveEntity = HBXMLRejectExternal;
    parser->sax->getParameterEntity = HBXMLRejectParameter;
    parser->sax->error = HBXMLSilent; parser->sax->fatalError = HBXMLSilent; parser->sax->warning = HBXMLSilent;
    parser->userData = parser;
    parser->replaceEntities = 0; parser->loadsubset = 0;
    parser->validate = 0; parser->recovery = 0; parser->keepBlanks = 1;
    result = xmlParseDocument(parser); document = parser->myDoc;
    valid = result == 0 && parser->wellFormed && document && !document->intSubset && !document->extSubset && xmlDocGetRootElement(document);
    parser->myDoc = NULL;
    xmlFreeParserCtxt(parser);
    if (!valid && document) xmlFreeDoc(document);
    return valid ? document : NULL;
}
