## Fijación de la cadena de suministro de CI
Las acciones de GitHub están ancladas a ID de confirmación inmutables de 40 caracteres. el cercano
El comentario conserva la etiqueta de lanzamiento mantenible por humanos.
| Dependency | Selected release | Verified immutable reference |
| --- | --- | --- |
| `actions/checkout` | `v7.0.1` | `3d3c42e5aac5ba805825da76410c181273ba90b1` |
| `actions/setup-java` | `v6.0.0` | `dd06d9cba3e5552c54d9f8ea23572deb30010f7c` |
| `actions/upload-artifact` | `v7.0.1` | `043fb46d1a93c77aae656e7c1c64a875d1fc6a0a` |
| `actions/download-artifact` | `v8.0.1` | `3e5f45b2cfb9172054b4087a40e8e0b5a5461e7c` |
| `actions/github-script` | `v9.0.0` | `d746ffe35508b1917358783b479e04febd2b8f71` |
| `aws-actions/configure-aws-credentials` | `v6.2.4` | `cbe3b392738ccf3f987d68400dafcf4b0624a56c` |
| `aws-actions/amazon-ecr-login` | `v2.1.7` | `aded0d722166a37980e030aa969dda0bfe6b6947` |
| `docker/setup-buildx-action` | `v4.3.0` | `37fe631027851001ddb9b187196cc803df7f5f0e` |
| `docker/build-push-action` | `v7.3.0` | `53b7df96c91f9c12dcc8a07bcb9ccacbed38856a` |
| `docker/login-action` | `v4.6.0` | `dbcb813823bdd20940b903addbd779551569679f` |
| `docker/metadata-action` | `v6.2.0` | `dc802804100637a589fabce1cb79ff13a1411302` |
| `gitleaks/gitleaks-action` | `v3.0.0` | `e0c47f4f8be36e29cdc102c57e68cb5cbf0e8d1e` |
| `hashicorp/setup-terraform` | `v4.0.1` | `dfe3c3f87815947d99a8997f908cb6525fc44e9e` |
| `anchore/sbom-action` | `v0.24.2` | `006b7ce8314066bdf1765b4500370d40fa6917a3` |
| `sigstore/cosign-installer` | `v4.1.2` | `6f9f17788090df1f26f669e9d70d6ae9567deba6` |
| `returntocorp/semgrep` | `1.99.0` | Deliberately fixed image tag (manifest verified) |

La verificación se realizó con respecto a las fuentes oficiales:
```sh
git ls-remote --refs https://github.com/actions/checkout.git refs/tags/v7.0.1
docker manifest inspect returntocorp/semgrep:1.99.0
```

`semgrep --config=auto --error --quiet` se ejecuta sin `continue-on-error` y
Quality Gate falla si Semgrep (o cualquiera de los controles de seguridad entre pares) no lo hace.
devolver `success`. Dependabot conserva su entrada al ecosistema `github-actions` por lo que
puede proponer futuras actualizaciones de pines de acción; Actualizaciones de Maven, GitHub Actions y Docker
use un tiempo de reutilización predeterminado de siete días.
