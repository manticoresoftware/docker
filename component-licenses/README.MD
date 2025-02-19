# Component Licenses

The **Docker image for Manticore Search** includes multiple third-party components, each distributed under its respective open-source license. This document provides an overview of these components, their sources, and licensing details.

## Manticore Search

**Website:** [Manticore Search](https://manticoresearch.com)  
**Source:** [GitHub Repository](https://github.com/manticoresoftware/manticoresearch)

**Copyright:**
```plaintext
Copyright (c) 2020-2024, Manticore Software LTD
All rights reserved.
```
**License:** [GPL v3 or later](https://raw.githubusercontent.com/manticoresoftware/manticoresearch/master/LICENSE)

## Components Used in Manticore Search

### Manticore Columnar Library

**Website:** [Manticore Columnar Library](https://github.com/manticoresoftware/columnar)  
**Source:** [GitHub Repository](https://github.com/manticoresoftware/columnar)

Manticore Search uses the **Manticore Columnar Library** for improved storage efficiency and query performance. The library is utilized during compilation and dynamically loaded at runtime.

**License:** [Apache 2.0](https://raw.githubusercontent.com/manticoresoftware/columnar/master/LICENSE)

---

### Manticore Executor

**Source:** Internal Manticore component

Manticore Executor is an execution engine used for query processing within Manticore Search.

**License:** Distributed under an open-source license, included in the [manticore-executor-license](./manticore-executor-license) file.

---

### Manticore Search Backup

**Source:** Internal Manticore component

Manticore Search Backup is a tool used for managing data backups within Manticore Search.

**License:** Distributed under an open-source license, included in the [manticoresearch-backup-license](./manticoresearch-backup-license) file.

---

### Manticore Search Buddy

**Source:** Internal Manticore component

Manticore Search Buddy is a management and optimization utility for Manticore Search instances.

**License:** Distributed under an open-source license, included in the [manticoresearch-buddy-license](./manticoresearch-buddy-license) file.

---

## License Compliance and Updates

1. **Adding a New Dependency**
    - If a new third-party dependency is added to the Docker image, its license must be retrieved and placed in this directory.
    - The file should be named appropriately, e.g., `new-component-license`.

2. **Updating Licenses**
    - When a component updates its licensing terms, the corresponding license file in this directory should be updated.

3. **Compliance**
    - This directory is included in the Docker image build to maintain legal compliance with open-source licenses.

For more details on Manticore Search licensing, refer to the [Manticore Search License](https://github.com/manticoresoftware/manticoresearch/blob/master/LICENSE).

