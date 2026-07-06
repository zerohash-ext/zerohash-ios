# Code Review Policy - ZerohashSDK iOS

## Overview

All code changes must undergo peer review before merging to ensure quality, security, and consistency.

---

## Requirements

- **All PRs require at least 1 approval**

---

## Before Submitting PR

1. Review your own diff
2. Run tests locally
3. Check for compiler warnings
4. Follow [Code Standards](CODE_STANDARDS.md)
5. Update documentation

---

## Review Focus

Reviewers check:

- **Correctness:** Does it work? Edge cases handled?
- **Standards:** Follows [Code Standards](CODE_STANDARDS.md)
- **Security:** No hardcoded secrets, proper validation
- **Testing:** Adequate coverage
- **Maintainability:** Readable and well-structured

---

**Examples:**
```
[BLOCKING] Mark delegate as weak to prevent retain cycle
[SUGGESTION] Consider extracting this into a separate method
[QUESTION] Why use force unwrap here?
[PRAISE] Great use of guard statements!
```

---

## Review Checklist

```
☐ Naming follows conventions (PascalCase/camelCase)
☐ Access modifiers explicit
☐ Delegates marked weak
☐ Public APIs documented with ///
☐ No sensitive data logged
☐ No hardcoded credentials
☐ Tests cover new functionality
☐ No compiler warnings
```

**Full standards:** See [Code Standards](CODE_STANDARDS.md)


## Resources

- [Code Standards](CODE_STANDARDS.md) - Coding conventions
- [PR Template](.github/pull_request_template.md) - PR checklist
