#include "fishhook.h"
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <mach-o/nlist.h>
#include <mach/mach.h>
#include <string.h>
#include <stdlib.h>
#include <stdbool.h>
#include <sys/mman.h>
#include <dlfcn.h>
#include <libkern/OSAtomic.h>

#ifdef __LP64__
#define SECTION section_64
#define SEGMENT_COMMAND segment_command_64
#define MACH_HEADER mach_header_64
#define NLIST nlist_64
#else
#define SECTION section
#define SEGMENT_COMMAND segment_command
#define MACH_HEADER mach_header
#define NLIST nlist
#endif

FISHHOOK_VISIBILITY
static struct rebindings_entry *_rebindings_head;

FISHHOOK_VISIBILITY
static int prepend_rebindings(struct rebindings_entry **rebindings_head, struct rebinding rebindings[], size_t nel) {
    struct rebindings_entry *new_entry = (struct rebindings_entry *)malloc(sizeof(struct rebindings_entry));
    if (!new_entry) return -1;
    new_entry->rebindings = (struct rebinding *)malloc(sizeof(struct rebinding) * nel);
    if (!new_entry->rebindings) { free(new_entry); return -1; }
    memcpy(new_entry->rebindings, rebindings, sizeof(struct rebinding) * nel);
    new_entry->rebindings_nel = nel;
    new_entry->next = *rebindings_head;
    *rebindings_head = new_entry;
    return 0;
}

FISHHOOK_VISIBILITY
static void perform_rebinding_with_section(struct rebindings_entry *rebindings, struct SECTION *section, intptr_t slide, struct NLIST *symtab, char *strtab, uint32_t *indirect_symtab) {
    uint32_t *indirect_symbol_indices = indirect_symtab + section->reserved1;
    void **indirect_symbol_bindings = (void **)((uintptr_t)section->addr + slide);
    for (uint32_t i = 0; i < section->size / sizeof(void *); i++) {
        uint32_t symtab_index = indirect_symbol_indices[i];
        if (symtab_index == INDIRECT_SYMBOL_ABS || symtab_index == INDIRECT_SYMBOL_LOCAL || symtab_index == (INDIRECT_SYMBOL_LOCAL | INDIRECT_SYMBOL_ABS)) continue;
        uint32_t strtab_offset = symtab[symtab_index].n_un.n_strx;
        char *symbol_name = strtab + strtab_offset;
        bool symbol_name_longer_than_1 = symbol_name[0] && symbol_name[1];
        struct rebindings_entry *cur = rebindings;
        while (cur) {
            for (uint32_t j = 0; j < cur->rebindings_nel; j++) {
                if (strcmp(&symbol_name[1], cur->rebindings[j].name) == 0) {
                    if (cur->rebindings[j].replaced != NULL && indirect_symbol_bindings[i] != cur->rebindings[j].replacement) {
                        *(cur->rebindings[j].replaced) = indirect_symbol_bindings[i];
                    }
                    indirect_symbol_bindings[i] = cur->rebindings[j].replacement;
                    goto symbol_loop;
                }
            }
            cur = cur->next;
        }
        symbol_loop:;
    }
}

FISHHOOK_VISIBILITY
static void rebind_symbols_for_image(struct rebindings_entry *rebindings, const struct MACH_HEADER *header, intptr_t slide) {
    Dl_info info;
    if (dladdr(header, &info) == 0) return;
    struct SEGMENT_COMMAND *cur_seg_cmd;
    struct SEGMENT_COMMAND *linkedit_segment = NULL;
    struct symtab_command *symtab_cmd = NULL;
    struct dysymtab_command *dysymtab_cmd = NULL;
    uintptr_t cur = (uintptr_t)header + sizeof(struct MACH_HEADER);
    for (uint32_t i = 0; i < header->ncmds; i++, cur += cur_seg_cmd->cmdsize) {
        cur_seg_cmd = (struct SEGMENT_COMMAND *)cur;
        if (cur_seg_cmd->cmd == LC_SEGMENT_ARCH_DEPENDENT) {
            if (strcmp(cur_seg_cmd->segname, SEG_LINKEDIT) == 0) linkedit_segment = cur_seg_cmd;
        } else if (cur_seg_cmd->cmd == LC_SYMTAB) {
            symtab_cmd = (struct symtab_command *)cur_seg_cmd;
        } else if (cur_seg_cmd->cmd == LC_DYSYMTAB) {
            dysymtab_cmd = (struct dysymtab_command *)cur_seg_cmd;
        }
    }
    if (!symtab_cmd || !dysymtab_cmd || !linkedit_segment) return;
    uintptr_t linkedit_base = (uintptr_t)linkedit_segment->vmaddr + slide - linkedit_segment->fileoff;
    struct NLIST *symtab = (struct NLIST *)(linkedit_base + symtab_cmd->symoff);
    char *strtab = (char *)(linkedit_base + symtab_cmd->stroff);
    uint32_t *indirect_symtab = (uint32_t *)(linkedit_base + dysymtab_cmd->indirectsymoff);
    cur = (uintptr_t)header + sizeof(struct MACH_HEADER);
    for (uint32_t i = 0; i < header->ncmds; i++, cur += cur_seg_cmd->cmdsize) {
        cur_seg_cmd = (struct SEGMENT_COMMAND *)cur;
        if (cur_seg_cmd->cmd == LC_SEGMENT_ARCH_DEPENDENT) {
            if (strcmp(cur_seg_cmd->segname, SEG_DATA) == 0 || strcmp(cur_seg_cmd->segname, SEG_DATA_CONST) == 0) {
                for (uint32_t j = 0; j < cur_seg_cmd->nsects; j++) {
                    struct SECTION *sect = (struct SECTION *)(cur + sizeof(struct SEGMENT_COMMAND)) + j;
                    if ((sect->flags & SECTION_TYPE) == S_LAZY_SYMBOL_POINTERS) {
                        perform_rebinding_with_section(rebindings, sect, slide, symtab, strtab, indirect_symtab);
                    }
                    if ((sect->flags & SECTION_TYPE) == S_NON_LAZY_SYMBOL_POINTERS) {
                        perform_rebinding_with_section(rebindings, sect, slide, symtab, strtab, indirect_symtab);
                    }
                }
            }
        }
    }
}

FISHHOOK_VISIBILITY
static void _rebind_symbols_for_image(const struct MACH_HEADER *header, intptr_t slide) {
    rebind_symbols_for_image(_rebindings_head, header, slide);
}

FISHHOOK_VISIBILITY
int rebind_symbols(struct rebinding rebindings[], size_t rebindings_nel) {
    int ret = prepend_rebindings(&_rebindings_head, rebindings, rebindings_nel);
    if (ret != 0) return ret;
    int image_count = _dyld_image_count();
    for (uint32_t i = 0; i < image_count; i++) {
        _rebind_symbols_for_image(_dyld_get_image_header(i), _dyld_get_image_vmaddr_slide(i));
    }
    static bool once = false;
    if (!once) {
        once = true;
        _dyld_register_func_for_add_image(_rebind_symbols_for_image);
    }
    return 0;
}

FISHHOOK_VISIBILITY
int rebind_symbols_image(void *header, intptr_t slide, struct rebinding rebindings[], size_t rebindings_nel) {
    struct rebindings_entry *rebindings_head = NULL;
    int ret = prepend_rebindings(&rebindings_head, rebindings, rebindings_nel);
    if (ret != 0) return ret;
    rebind_symbols_for_image(rebindings_head, (const struct MACH_HEADER *)header, slide);
    free(rebindings_head->rebindings);
    free(rebindings_head);
    return 0;
}
