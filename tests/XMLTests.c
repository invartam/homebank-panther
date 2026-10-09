#include "HBXML.h"
#include <libxml/parser.h>
#include <libxml/globals.h>
#include <stdio.h>
#include <string.h>

static int failures, checks, externalLoads;
static void check(int ok, const char *message) { checks++; if (!ok) { failures++; fprintf(stderr, "FAIL: %s\n", message); } }
static xmlParserInputPtr blockedLoader(const char *url, const char *id, xmlParserCtxtPtr context) {
    (void)url; (void)id; (void)context; externalLoads++; return NULL;
}
static xmlDocPtr parse(const char *text) { return HBXMLDocument(text, (unsigned long)strlen(text)); }
static void refuses(const char *text, const char *message) {
    xmlDocPtr doc = parse(text); check(doc == NULL, message); if (doc) xmlFreeDoc(doc);
}
int main(void) {
    xmlExternalEntityLoader original = xmlGetExternalEntityLoader();
    int substitutions = xmlSubstituteEntitiesDefault(1), subsets = xmlLoadExtDtdDefaultValue;
    xmlLoadExtDtdDefaultValue = 1; xmlSetExternalEntityLoader(blockedLoader);
    xmlDocPtr doc = parse("<homebank v='1.6'><!--keep--><account name='A &amp; B'/></homebank>");
    check(doc != NULL, "legacy memory parser constructs a DOM with ordinary entities and comments");
    if (doc) {
        xmlNodePtr child = xmlDocGetRootElement(doc)->children;
        while (child && child->type != XML_ELEMENT_NODE) child = child->next;
        xmlChar *name = child ? xmlGetProp(child, BAD_CAST "name") : NULL;
        check(name && xmlStrEqual(name, BAD_CAST "A & B"), "predefined XML entities retain their values");
        if (name) xmlFree(name); xmlFreeDoc(doc);
    }
    doc = parse("<homebank xmlns:x='urn:test' v='1.6'><x:extension x:value='kept'/></homebank>");
    check(doc && xmlDocGetRootElement(doc)->children && xmlDocGetRootElement(doc)->children->ns && xmlStrEqual(xmlDocGetRootElement(doc)->children->ns->href, BAD_CAST "urn:test"), "runtime namespace callbacks remain intact with old headers");
    if (doc) xmlFreeDoc(doc);
    int i, complete = 1;
    for (i = 0; i < 100; i++) { doc = parse("<homebank v='1.6'><ope st='2'/></homebank>"); if (!doc) { complete = 0; break; } xmlFreeDoc(doc); }
    check(complete, "repeated document creation and cleanup retain valid callback lifetimes");
    refuses("<!DOCTYPE homebank><homebank v='1.6'/>", "empty DOCTYPE is refused");
    refuses("<!DOCTYPE homebank SYSTEM 'https://attacker.invalid/wallet.dtd'><homebank v='1.6'/>", "remote DTD is refused before loading");
    refuses("<!DOCTYPE homebank [<!ENTITY bank SYSTEM 'file:///fictive/private-data'>]><homebank v='1.6' memo='&bank;'/>", "local external entity is refused before reading");
    refuses("<!DOCTYPE homebank [<!ENTITY % p SYSTEM 'https://attacker.invalid/e'>%p;]><homebank v='1.6'/>", "external parameter entity is refused");
    refuses("<!DOCTYPE homebank [<!ENTITY a 'secret'>]><homebank v='1.6' memo='&a;'/>", "internal declared entities are refused");
    refuses("<homebank v='1.6'>", "incomplete DOM is never returned");
    refuses("<homebank v='1.6' memo='&undefined;'/>", "undefined entity is refused");
    check(HBXMLDocument(NULL, 0) == NULL && HBXMLDocument("x", 9UL * 1024 * 1024) == NULL, "input is bounded before parser allocation");
    check(externalLoads == 0, "no external loader was invoked even with hostile global defaults");
    check(xmlGetExternalEntityLoader() == blockedLoader && xmlLoadExtDtdDefaultValue == 1, "reader does not change global entity or DTD settings");
    xmlSetExternalEntityLoader(original); xmlLoadExtDtdDefaultValue = subsets; xmlSubstituteEntitiesDefault(substitutions);
    printf("%d/%d XML safety checks passed (headers %s, runtime %s, no external I/O)\n", checks - failures, checks, LIBXML_DOTTED_VERSION, xmlParserVersion);
    return failures ? 1 : 0;
}
