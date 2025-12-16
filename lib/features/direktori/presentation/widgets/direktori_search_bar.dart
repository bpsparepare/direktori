import 'package:flutter/material.dart';

class DirektoriSearchBar extends StatefulWidget {
  final TextEditingController controller;
  final Function(String) onSearch;

  const DirektoriSearchBar({
    Key? key,
    required this.controller,
    required this.onSearch,
  }) : super(key: key);

  @override
  State<DirektoriSearchBar> createState() => _DirektoriSearchBarState();
}

class _DirektoriSearchBarState extends State<DirektoriSearchBar> {
  void _controllerListener() {
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_controllerListener);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_controllerListener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: TextField(
        controller: widget.controller,
        decoration: InputDecoration(
          hintText: 'Cari nama usaha...',
          prefixIcon: const Icon(Icons.search, color: Colors.grey),
          suffixIcon: widget.controller.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: Colors.grey),
                  onPressed: () {
                    setState(() {
                      widget.controller.clear();
                    });
                    widget.onSearch('');
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
        onSubmitted: (value) => widget.onSearch(value.trim()),
        onChanged: (value) {
          setState(() {}); // To update suffixIcon visibility
          // Debounce search
          Future.delayed(const Duration(milliseconds: 500), () {
            if (widget.controller.text == value) {
              widget.onSearch(value.trim());
            }
          });
        },
      ),
    );
  }
}
