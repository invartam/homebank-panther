/* Compatibility probe based on HomeBank 5.10.3 src/hb-xml.c:hb_xml_get_version.
 * This checks its bounded prefix/version detection and actual GLib GMarkup,
 * not HomeBank's account loader or GUI. Only fictive exports are used in tests.
 */
#include <glib.h>
#include <stdio.h>

int main(int argc, char **argv) {
    gchar *buffer = NULL; gsize length = 0; GError *error = NULL;
    if (argc != 2 || !g_file_get_contents(argv[1], &buffer, &length, &error)) {
        fprintf(stderr, "Fichier de test inaccessible.\n"); if (error) g_error_free(error); return 1;
    }
    gchar *version = g_strstr_len(buffer, 50, "<homebank v=");
    if (!version || g_ascii_strtod(version + 13, NULL) <= 0 || g_ascii_strtod(version + 13, NULL) > 1.6) {
        fprintf(stderr, "Signature/version refusee par le controle HomeBank original.\n"); g_free(buffer); return 1;
    }
    GMarkupParser parser = { NULL, NULL, NULL, NULL, NULL };
    GMarkupParseContext *context = g_markup_parse_context_new(&parser, 0, NULL, NULL);
    gboolean ok = g_markup_parse_context_parse(context, buffer, length, &error);
    if (ok) ok = g_markup_parse_context_end_parse(context, &error);
    if (!ok) fprintf(stderr, "GLib GMarkup refuse le XML de test.\n");
    if (error) g_error_free(error); g_markup_parse_context_free(context); g_free(buffer);
    if (ok) printf("Signature HomeBank et GLib GMarkup : OK\n");
    return ok ? 0 : 1;
}
