# Changelog

## [0.1.2](https://github.com/rcgsheffield/stanage-llm/compare/v0.1.1...v0.1.2) (2026-11-04)


### Bug Fixes

* clone over HTTPS so new users don't need an SSH key ([#39](https://github.com/rcgsheffield/stanage-llm/issues/39)) ([875d0f7](https://github.com/rcgsheffield/stanage-llm/commit/875d0f7f4e63e673483566b507735a3dcd2aaa89)), closes [#38](https://github.com/rcgsheffield/stanage-llm/issues/38)
* run setup on a worker node, since Apptainer isn't on login nodes ([#42](https://github.com/rcgsheffield/stanage-llm/issues/42)) ([cf7ec73](https://github.com/rcgsheffield/stanage-llm/commit/cf7ec73d85d12a32bb2673ef6b98ce7c92f0879a)), closes [#41](https://github.com/rcgsheffield/stanage-llm/issues/41)
* scope stop_ollama (and the idle watchdog) to the current session's server ([#16](https://github.com/rcgsheffield/stanage-llm/issues/16)) ([abb2d02](https://github.com/rcgsheffield/stanage-llm/commit/abb2d0213e2d1f818d008edc96e174a59bd70abc))

## [0.1.1](https://github.com/rcgsheffield/stanage-llm/compare/v0.1.0...v0.1.1) (2026-07-28)


### Bug Fixes

* fastdata area was created world-readable; document who can see your data ([#35](https://github.com/rcgsheffield/stanage-llm/issues/35)) ([9c280b7](https://github.com/rcgsheffield/stanage-llm/commit/9c280b7860223f16c1f260631b6ffa2dad6b697e))
