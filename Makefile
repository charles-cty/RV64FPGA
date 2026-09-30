.PHONY: test test-iss test-xsim test-m4 test-m5 core-random-diff soc-random-diff soc-mmu-tlb-diff mmu-random uart-rx soc-uart-irq ddr3-mig-atomic ddr3-external vivado-project-check vivado-synth vivado-impl linux-handoff boot-image jtag-smoke-image linux-stack dts

test: test-iss

test-iss:
	uv run python -m unittest discover -s tests

test-xsim:
	./scripts/run-xsim.sh alu

test-m4:
	./scripts/run-m4-regression.sh

test-m5:
	./scripts/run-m5-model-regression.sh

core-random-diff:
	./scripts/run-core-random-diff.sh

soc-random-diff:
	./scripts/run-soc-random-diff.sh

soc-mmu-tlb-diff:
	./scripts/run-soc-mmu-tlb-diff.sh

mmu-random:
	./scripts/run-xsim.sh mmu_random

uart-rx:
	./scripts/run-xsim.sh uart_rx

soc-uart-irq:
	./scripts/run-xsim.sh soc_uart_irq

ddr3-mig-atomic:
	./scripts/run-xsim.sh ddr3_mig_atomic_path

ddr3-external:
	./scripts/run-xsim.sh soc_ddr3_external

vivado-project-check:
	pwsh.exe -WorkingDirectory 'C:\Windows\Temp' -File "$$(wslpath -w scripts/validate-rv64-mig-project.ps1)" -SourceRoot "$$(wslpath -w .)"

vivado-synth: boot-image
	pwsh.exe -WorkingDirectory 'C:\Windows\Temp' -File "$$(wslpath -w scripts/synth-rv64-mig-project.ps1)" -SourceRoot "$$(wslpath -w .)" -OutputRoot "$$(wslpath -w build/vivado-synth)"

vivado-impl:
	pwsh.exe -WorkingDirectory 'C:\Windows\Temp' -File "$$(wslpath -w scripts/impl-rv64-mig-checkpoint.ps1)" -SourceRoot "$$(wslpath -w .)" -OutputRoot "$$(wslpath -w "$$(pwd)/build/vivado-impl")"

linux-handoff: boot-image
	./scripts/run-xsim.sh soc_linux_handoff

boot-image:
	./scripts/build-boot-image.sh

jtag-smoke-image:
	./scripts/build-jtag-smoke-image.sh

linux-stack:
	./scripts/build-linux-stack.sh

dts:
	uv run python tools/build_model_dtb.py build/rv64fpga-model.dtb

.PHONY: check-linux-baseline linux-acceptance-preflight
check-linux-baseline:
	python3 tools/check_linux_baseline.py

linux-acceptance-preflight:
	python3 tools/run_linux_acceptance.py
