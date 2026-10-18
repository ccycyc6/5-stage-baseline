VERILATOR ?= verilator
OBJ_DIR    ?= $(CURDIR)/obj_dir
COMMON_FLAGS := --binary --timing --Wall --Wno-fatal

VECTOR_SOURCES := \
	$(CURDIR)/rtl/vector/vpu_pkg.sv \
	$(CURDIR)/rtl/vector/vpu_vector_regfile.sv \
	$(CURDIR)/rtl/vector/vpu_vector_alu.sv \
	$(CURDIR)/rtl/control/vpu_vector_controller.sv \
	$(CURDIR)/tb/control/tb_vpu_vector_controller.sv

UB_SOURCES := \
	$(CURDIR)/rtl/memory/unified_buffer.sv \
	$(CURDIR)/tb/memory/tb_unified_buffer.sv

DMA_SOURCES := \
	$(CURDIR)/rtl/memory/unified_buffer.sv \
	$(CURDIR)/rtl/memory/vpu_dma.sv \
	$(CURDIR)/tb/memory/tb_vpu_dma.sv

TENSOR_SOURCES := \
	$(CURDIR)/rtl/tensor/tensor_pkg.sv \
	$(CURDIR)/rtl/memory/unified_buffer.sv \
	$(CURDIR)/rtl/tensor/MXU/Systolic_Array/tensor_pe.sv \
	$(CURDIR)/rtl/tensor/MXU/Systolic_Array/tensor_systolic_array.sv \
	$(CURDIR)/rtl/tensor/MXU/INT8_GEMM/tensor_gemm_core.sv \
	$(CURDIR)/rtl/tensor/tensor_controller.sv \
	$(CURDIR)/rtl/tensor/Epilogue/tensor_epilogue_core.sv \
	$(CURDIR)/rtl/tensor/Epilogue/tensor_epilogue_controller.sv \
	$(CURDIR)/tb/tensor/tb_tensor_gemm_core.sv

TOP_SOURCES := \
	$(CURDIR)/rtl/interface/core_v_xif.sv \
	$(CURDIR)/rtl/common/minitensor_pkg.sv \
	$(CURDIR)/rtl/tensor/tensor_pkg.sv \
	$(CURDIR)/rtl/vector/vpu_pkg.sv \
	$(CURDIR)/rtl/vector/vpu_vector_regfile.sv \
	$(CURDIR)/rtl/vector/vpu_vector_alu.sv \
	$(CURDIR)/rtl/control/vpu_vector_controller.sv \
	$(CURDIR)/rtl/tensor/MXU/Systolic_Array/tensor_pe.sv \
	$(CURDIR)/rtl/tensor/MXU/Systolic_Array/tensor_systolic_array.sv \
	$(CURDIR)/rtl/tensor/MXU/INT8_GEMM/tensor_gemm_core.sv \
	$(CURDIR)/rtl/tensor/tensor_controller.sv \
	$(CURDIR)/rtl/tensor/Epilogue/tensor_epilogue_core.sv \
	$(CURDIR)/rtl/tensor/Epilogue/tensor_epilogue_controller.sv \
	$(CURDIR)/rtl/memory/unified_buffer.sv \
	$(CURDIR)/rtl/memory/vpu_dma.sv \
	$(CURDIR)/rtl/top/mini_tensor_top.sv \
	$(CURDIR)/tb/top/tb_mini_tensor_top.sv

NPC_SOURCES := \
	$(CURDIR)/rtl/interface/core_v_xif.sv \
	$(CURDIR)/rtl/common/minitensor_pkg.sv \
	$(CURDIR)/rtl/tensor/tensor_pkg.sv \
	$(CURDIR)/rtl/vector/vpu_pkg.sv \
	$(CURDIR)/rtl/vector/vpu_vector_regfile.sv \
	$(CURDIR)/rtl/vector/vpu_vector_alu.sv \
	$(CURDIR)/rtl/control/vpu_vector_controller.sv \
	$(CURDIR)/rtl/tensor/MXU/Systolic_Array/tensor_pe.sv \
	$(CURDIR)/rtl/tensor/MXU/Systolic_Array/tensor_systolic_array.sv \
	$(CURDIR)/rtl/tensor/MXU/INT8_GEMM/tensor_gemm_core.sv \
	$(CURDIR)/rtl/tensor/tensor_controller.sv \
	$(CURDIR)/rtl/tensor/Epilogue/tensor_epilogue_core.sv \
	$(CURDIR)/rtl/tensor/Epilogue/tensor_epilogue_controller.sv \
	$(CURDIR)/rtl/memory/unified_buffer.sv \
	$(CURDIR)/rtl/memory/vpu_dma.sv \
	$(CURDIR)/rtl/top/mini_tensor_top.sv \
	$(CURDIR)/tb/npc/mt_mem_model.sv \
	$(CURDIR)/tb/npc/vpu_npc_model.sv \
	$(CURDIR)/tb/top/tb_mini_tensor_npc.sv

.PHONY: sim regress npc-sim vector-sim vrf-sim ub-sim dma-sim tensor-sim tensor-controller-sim epilogue-sim top-sim clean

sim: top-sim

regress:
	$(MAKE) vector-sim
	$(MAKE) vrf-sim
	$(MAKE) ub-sim
	$(MAKE) dma-sim
	$(MAKE) tensor-sim
	$(MAKE) tensor-controller-sim
	$(MAKE) epilogue-sim
	$(MAKE) top-sim
	$(MAKE) npc-sim

npc-sim:
	mkdir -p $(OBJ_DIR)/npc
	CCACHE_DISABLE=1 $(VERILATOR) $(COMMON_FLAGS) $(VERILATOR_FLAGS) \
		--Mdir $(OBJ_DIR)/npc --top-module tb_mini_tensor_npc $(NPC_SOURCES)
	$(OBJ_DIR)/npc/Vtb_mini_tensor_npc

vector-sim:
	mkdir -p $(OBJ_DIR)/vector
	CCACHE_DISABLE=1 $(VERILATOR) $(COMMON_FLAGS) $(VERILATOR_FLAGS) \
		--Mdir $(OBJ_DIR)/vector --top-module tb_vpu_vector_controller $(VECTOR_SOURCES)
	$(OBJ_DIR)/vector/Vtb_vpu_vector_controller

vrf-sim:
	mkdir -p $(OBJ_DIR)/vrf
	CCACHE_DISABLE=1 $(VERILATOR) $(COMMON_FLAGS) --Mdir $(OBJ_DIR)/vrf \
		--top-module tb_vpu_vector_regfile \
		$(CURDIR)/rtl/vector/vpu_vector_regfile.sv \
		$(CURDIR)/tb/vector/tb_vpu_vector_regfile.sv
	$(OBJ_DIR)/vrf/Vtb_vpu_vector_regfile

ub-sim:
	mkdir -p $(OBJ_DIR)/ub
	CCACHE_DISABLE=1 $(VERILATOR) $(COMMON_FLAGS) --Mdir $(OBJ_DIR)/ub \
		--top-module tb_unified_buffer $(UB_SOURCES)
	$(OBJ_DIR)/ub/Vtb_unified_buffer

dma-sim:
	mkdir -p $(OBJ_DIR)/dma
	CCACHE_DISABLE=1 $(VERILATOR) $(COMMON_FLAGS) --Mdir $(OBJ_DIR)/dma \
		--top-module tb_vpu_dma $(DMA_SOURCES)
	$(OBJ_DIR)/dma/Vtb_vpu_dma

tensor-sim:
	mkdir -p $(OBJ_DIR)/tensor
	CCACHE_DISABLE=1 $(VERILATOR) $(COMMON_FLAGS) --Mdir $(OBJ_DIR)/tensor \
		--top-module tb_tensor_gemm_core $(TENSOR_SOURCES)
	$(OBJ_DIR)/tensor/Vtb_tensor_gemm_core

tensor-controller-sim:
	mkdir -p $(OBJ_DIR)/tensor_controller
	CCACHE_DISABLE=1 $(VERILATOR) $(COMMON_FLAGS) --Mdir $(OBJ_DIR)/tensor_controller \
		--top-module tb_tensor_controller \
		$(CURDIR)/rtl/tensor/tensor_pkg.sv \
		$(CURDIR)/rtl/memory/unified_buffer.sv \
		$(CURDIR)/rtl/tensor/MXU/Systolic_Array/tensor_pe.sv \
		$(CURDIR)/rtl/tensor/MXU/Systolic_Array/tensor_systolic_array.sv \
		$(CURDIR)/rtl/tensor/MXU/INT8_GEMM/tensor_gemm_core.sv \
		$(CURDIR)/rtl/tensor/tensor_controller.sv \
		$(CURDIR)/tb/tensor/tb_tensor_controller.sv
	$(OBJ_DIR)/tensor_controller/Vtb_tensor_controller

epilogue-sim:
	mkdir -p $(OBJ_DIR)/epilogue
	CCACHE_DISABLE=1 $(VERILATOR) $(COMMON_FLAGS) --Mdir $(OBJ_DIR)/epilogue \
		--top-module tb_tensor_epilogue \
		$(CURDIR)/rtl/tensor/Epilogue/tensor_epilogue_core.sv \
		$(CURDIR)/tb/tensor/tb_tensor_epilogue.sv
	$(OBJ_DIR)/epilogue/Vtb_tensor_epilogue

top-sim:
	mkdir -p $(OBJ_DIR)/top
	CCACHE_DISABLE=1 $(VERILATOR) $(COMMON_FLAGS) --Mdir $(OBJ_DIR)/top \
		--top-module tb_mini_tensor_top $(TOP_SOURCES)
	$(OBJ_DIR)/top/Vtb_mini_tensor_top

clean:
	rm -rf $(OBJ_DIR)
