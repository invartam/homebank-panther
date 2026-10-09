#ifndef HB_XML_H
#define HB_XML_H
#include <libxml/tree.h>

/* Returns an owned DOM or NULL; never loads DTDs or external entities. */
xmlDocPtr HBXMLDocument(const char *bytes, unsigned long length);
#endif
