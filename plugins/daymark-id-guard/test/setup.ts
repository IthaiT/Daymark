// CodeMirror uses layout APIs that a headless DOM does not implement.
Range.prototype.getClientRects = () => [] as unknown as DOMRectList;
Range.prototype.getBoundingClientRect = () => new DOMRect();
