import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/term.dart';
import '../../../shared/providers/network_providers.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../../reader/models/term_form.dart';
import '../../reader/models/term_tooltip.dart';
import '../../reader/widgets/term_form.dart' show TermFormWidget;

class TermEditDialogWrapper extends ConsumerStatefulWidget {
  final Term term;
  final VoidCallback onDelete;
  final void Function(Term)? onSave;

  const TermEditDialogWrapper({
    super.key,
    required this.term,
    required this.onDelete,
    this.onSave,
  });

  @override
  ConsumerState<TermEditDialogWrapper> createState() =>
      _TermEditDialogWrapperState();
}

class _TermEditDialogWrapperState extends ConsumerState<TermEditDialogWrapper> {
  TermForm? _termForm;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadTermForm();
  }

  Term _createTermFromForm(TermForm form) {
    return Term(
      id: form.termId!,
      text: form.term,
      translation: form.translation,
      status: form.status,
      langId: form.languageId,
      language: widget.term.language,
      tags: form.tags,
      createdDate: widget.term.createdDate,
    );
  }

  Future<void> _loadTermForm() async {
    try {
      final contentService = ref.read(contentServiceProvider);
      _termForm = await contentService.getTermFormByIdWithParentDetails(
        widget.term.id,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to load term: $e')));
        Navigator.pop(context);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _termForm == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return AnimatedPadding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOut,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).appBarTheme.backgroundColor,
              border: Border(
                bottom: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Edit Term',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (_isSaving)
                  const Padding(
                    padding: EdgeInsets.only(right: 12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Delete Term'),
                        content: const Text(
                          'Are you sure you want to delete this term?',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                              widget.onDelete();
                            },
                            child: Text(
                              'Delete',
                              style: TextStyle(
                                color: context.appColorScheme.error.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(8),
              child: TermFormWidget(
                termForm: _termForm!,
                onSave: (updatedForm) async {
                  try {
                    final contentService = ref.read(contentServiceProvider);
                    await contentService.editTerm(
                      updatedForm.termId!,
                      updatedForm.toFormData(),
                    );
                    if (mounted) {
                      final updatedTerm = _createTermFromForm(updatedForm);
                      widget.onSave?.call(updatedTerm);
                      Navigator.pop(context);
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to update term: $e')),
                      );
                    }
                  }
                },
                onUpdate: (updatedForm) async {
                  setState(() {
                    _termForm = updatedForm;
                  });
                  try {
                    setState(() {
                      _isSaving = true;
                    });
                    final contentService = ref.read(contentServiceProvider);
                    await contentService.editTerm(
                      updatedForm.termId!,
                      updatedForm.toFormData(),
                    );
                    if (mounted) {
                      final updatedTerm = _createTermFromForm(updatedForm);
                      widget.onSave?.call(updatedTerm);
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to update term: $e')),
                      );
                    }
                  } finally {
                    if (mounted) {
                      setState(() {
                        _isSaving = false;
                      });
                    }
                  }
                },
                onCancel: () => Navigator.pop(context),
                onParentDoubleTap: (parent) => _showParentTermForm(parent),
                contentService: ref.read(contentServiceProvider),
                dictionaryService: ref.read(dictionaryServiceProvider),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showParentTermForm(TermParent parent) async {
    try {
      final contentService = ref.read(contentServiceProvider);
      TermForm? parentTermForm;
      if (parent.id != null) {
        parentTermForm = await contentService.getTermFormById(parent.id!);
      } else if (_termForm != null) {
        parentTermForm =
            await contentService.getTermForm(_termForm!.languageId, parent.term);
      }
      if (parentTermForm != null && mounted) {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          enableDrag: false,
          backgroundColor: const Color(0x00000000),
          builder: (bottomSheetContext) {
            var currentForm = parentTermForm!;
            return AnimatedPadding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(bottomSheetContext).viewInsets.bottom,
              ),
              duration: const Duration(milliseconds: 100),
              curve: Curves.easeOut,
              child: StatefulBuilder(
                builder: (context, setModalState) {
                  return TermFormWidget(
                    termForm: currentForm,
                    onUpdate: (updatedForm) {
                      currentForm = updatedForm;
                      setModalState(() {});
                    },
                  onSave: (updatedForm) async {
                    try {
                      if (updatedForm.termId != null) {
                        await contentService.editTerm(
                          updatedForm.termId!,
                          updatedForm.toFormData(),
                        );
                      } else {
                        await contentService.saveTermForm(
                          updatedForm.languageId,
                          updatedForm.term,
                          updatedForm.toFormData(),
                        );
                      }
                      if (mounted) {
                        final updatedParent = TermParent(
                          id: updatedForm.termId,
                          term: updatedForm.term,
                          translation: updatedForm.translation,
                          status: int.tryParse(updatedForm.status),
                          syncStatus: updatedForm.syncStatus,
                        );
                        final updatedParents =
                            (_termForm?.parents ?? []).map((p) {
                          final matchById = updatedParent.id != null &&
                              p.id != null &&
                              p.id == updatedParent.id;
                          final matchByTerm = p.term.trim().toLowerCase() ==
                              updatedParent.term.trim().toLowerCase();
                          if (matchById || matchByTerm) {
                            return updatedParent;
                          }
                          return p;
                        }).toList();
                        setState(() {
                          _termForm =
                              _termForm?.copyWith(parents: updatedParents);
                        });
                        Navigator.pop(bottomSheetContext);
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content:
                                Text('Failed to save parent term: $e'),
                          ),
                        );
                      }
                    }
                  },
                  onCancel: () => Navigator.pop(bottomSheetContext),
                  contentService: ref.read(contentServiceProvider),
                  dictionaryService: ref.read(dictionaryServiceProvider),
                );
              },
            ),
          );
        },
      );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load parent term: $e')),
        );
      }
    }
  }
}
