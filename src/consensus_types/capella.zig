const std = @import("std");
const ssz = @import("ssz");
const p = @import("primitive.zig");
const c = @import("constants.zig");
const preset = @import("preset.zig").active_preset;
const phase0 = @import("phase0.zig");
const altair = @import("altair.zig");
const bellatrix = @import("bellatrix.zig");

pub const Fork = phase0.Fork;
pub const ForkData = phase0.ForkData;
pub const Checkpoint = phase0.Checkpoint;
pub const Validator = phase0.Validator;
pub const AttestationData = phase0.AttestationData;
pub const IndexedAttestation = phase0.IndexedAttestation;
pub const PendingAttestation = phase0.PendingAttestation;
pub const Eth1Data = phase0.Eth1Data;
pub const HistoricalBatch = phase0.HistoricalBatch;
pub const DepositMessage = phase0.DepositMessage;
pub const DepositData = phase0.DepositData;
pub const BeaconBlockHeader = phase0.BeaconBlockHeader;
pub const SigningData = phase0.SigningData;
pub const ProposerSlashing = phase0.ProposerSlashing;
pub const AttesterSlashing = phase0.AttesterSlashing;
pub const Attestation = phase0.Attestation;
pub const Deposit = phase0.Deposit;
pub const VoluntaryExit = phase0.VoluntaryExit;
pub const SignedVoluntaryExit = phase0.SignedVoluntaryExit;
pub const Eth1Block = phase0.Eth1Block;
pub const AggregateAndProof = phase0.AggregateAndProof;
pub const SignedAggregateAndProof = phase0.SignedAggregateAndProof;
pub const HistoricalBlockRoots = phase0.HistoricalBlockRoots;
pub const HistoricalStateRoots = phase0.HistoricalStateRoots;
pub const ProposerSlashings = phase0.ProposerSlashings;
pub const AttesterSlashings = phase0.AttesterSlashings;
pub const Attestations = phase0.Attestations;
pub const Deposits = phase0.Deposits;
pub const VoluntaryExits = phase0.VoluntaryExits;

pub const SyncAggregate = altair.SyncAggregate;
pub const SyncCommittee = altair.SyncCommittee;
pub const SyncCommitteeMessage = altair.SyncCommitteeMessage;
pub const SyncCommitteeContribution = altair.SyncCommitteeContribution;
pub const ContributionAndProof = altair.ContributionAndProof;
pub const SignedContributionAndProof = altair.SignedContributionAndProof;
pub const SyncAggregatorSelectionData = altair.SyncAggregatorSelectionData;

pub const PowBlock = bellatrix.PowBlock;
pub const LogsBloom = bellatrix.LogsBloom;
pub const ExtraData = bellatrix.ExtraData;

pub const LightClientHeader = ssz.VariableContainerType(struct {
    beacon: BeaconBlockHeader,
    execution: ExecutionPayloadHeader,
    execution_branch: ssz.FixedVectorType(p.Bytes32, @floor(@log2(@as(f32, @floatFromInt(c.EXECUTION_PAYLOAD_GINDEX))))),
});

pub const LightClientBootstrap = ssz.VariableContainerType(struct {
    header: LightClientHeader,
    current_sync_committee: SyncCommittee,
    current_sync_committee_branch: ssz.FixedVectorType(p.Bytes32, @floor(@log2(@as(f32, @floatFromInt(c.CURRENT_SYNC_COMMITTEE_GINDEX))))),
});

pub const LightClientUpdate = ssz.VariableContainerType(struct {
    attested_header: LightClientHeader,
    next_sync_committee: SyncCommittee,
    next_sync_committee_branch: ssz.FixedVectorType(p.Bytes32, @floor(@log2(@as(f32, @floatFromInt(c.NEXT_SYNC_COMMITTEE_GINDEX))))),
    finalized_header: LightClientHeader,
    finality_branch: ssz.FixedVectorType(p.Bytes32, @floor(@log2(@as(f32, @floatFromInt(c.FINALIZED_ROOT_GINDEX))))),
    sync_aggregate: SyncAggregate,
    signature_slot: p.Slot,
});

pub const LightClientFinalityUpdate = ssz.VariableContainerType(struct {
    attested_header: LightClientHeader,
    finalized_header: LightClientHeader,
    finality_branch: ssz.FixedVectorType(p.Bytes32, @floor(@log2(@as(f32, @floatFromInt(c.FINALIZED_ROOT_GINDEX))))),
    sync_aggregate: SyncAggregate,
    signature_slot: p.Slot,
});

pub const LightClientOptimisticUpdate = ssz.VariableContainerType(struct {
    attested_header: LightClientHeader,
    sync_aggregate: SyncAggregate,
    signature_slot: p.Slot,
});

pub const Withdrawal = ssz.FixedContainerType(struct {
    index: p.WithdrawalIndex,
    validator_index: p.ValidatorIndex,
    address: p.ExecutionAddress,
    amount: p.Gwei,
});

pub const BLSToExecutionChange = ssz.FixedContainerType(struct {
    validator_index: p.ValidatorIndex,
    from_bls_pubkey: p.BLSPubkey,
    to_execution_address: p.ExecutionAddress,
});

pub const SignedBLSToExecutionChange = ssz.FixedContainerType(struct {
    message: BLSToExecutionChange,
    signature: p.BLSSignature,
});

pub const SignedBLSToExecutionChanges = ssz.FixedListType(SignedBLSToExecutionChange, preset.MAX_BLS_TO_EXECUTION_CHANGES);

pub const HistoricalSummary = ssz.FixedContainerType(struct {
    block_summary_root: p.Root,
    state_summary_root: p.Root,
});

pub const ExecutionPayload = ssz.VariableContainerType(struct {
    parent_hash: p.Bytes32,
    fee_recipient: p.Bytes20,
    state_root: p.Bytes32,
    receipts_root: p.Bytes32,
    logs_bloom: LogsBloom,
    prev_randao: p.Bytes32,
    block_number: p.Uint64,
    gas_limit: p.Uint64,
    gas_used: p.Uint64,
    timestamp: p.Uint64,
    extra_data: ExtraData,
    base_fee_per_gas: p.Uint256,
    block_hash: p.Bytes32,
    transactions: ssz.VariableListType(ssz.ByteListType(preset.MAX_BYTES_PER_TRANSACTION), preset.MAX_TRANSACTIONS_PER_PAYLOAD),
    withdrawals: ssz.FixedListType(Withdrawal, preset.MAX_WITHDRAWALS_PER_PAYLOAD),
});

pub const ExecutionPayloadHeader = ssz.VariableContainerType(struct {
    parent_hash: p.Bytes32,
    fee_recipient: p.Bytes20,
    state_root: p.Bytes32,
    receipts_root: p.Bytes32,
    logs_bloom: LogsBloom,
    prev_randao: p.Bytes32,
    block_number: p.Uint64,
    gas_limit: p.Uint64,
    gas_used: p.Uint64,
    timestamp: p.Uint64,
    extra_data: ExtraData,
    base_fee_per_gas: p.Uint256,
    block_hash: p.Bytes32,
    transactions_root: p.Root,
    withdrawals_root: p.Root,
});

pub const BeaconBlockBody = ssz.VariableContainerType(struct {
    randao_reveal: p.BLSSignature,
    eth1_data: Eth1Data,
    graffiti: p.Bytes32,
    proposer_slashings: ProposerSlashings,
    attester_slashings: AttesterSlashings,
    attestations: Attestations,
    deposits: Deposits,
    voluntary_exits: VoluntaryExits,
    sync_aggregate: SyncAggregate,
    execution_payload: ExecutionPayload,
    bls_to_execution_changes: SignedBLSToExecutionChanges,
});

pub const BeaconBlock = ssz.VariableContainerType(struct {
    slot: p.Slot,
    proposer_index: p.ValidatorIndex,
    parent_root: p.Root,
    state_root: p.Root,
    body: BeaconBlockBody,
});

pub const SignedBeaconBlockHeader = ssz.FixedContainerType(struct {
    message: BeaconBlockHeader,
    signature: p.BLSSignature,
});

pub const BeaconState = ssz.VariableContainerType(struct {
    genesis_time: p.Uint64,
    genesis_validators_root: p.Root,
    slot: p.Slot,
    fork: Fork,
    latest_block_header: BeaconBlockHeader,
    block_roots: HistoricalBlockRoots,
    state_roots: HistoricalStateRoots,
    historical_roots: ssz.FixedListType(p.Root, preset.HISTORICAL_ROOTS_LIMIT),
    eth1_data: Eth1Data,
    eth1_data_votes: phase0.Eth1DataVotes,
    eth1_deposit_index: p.Uint64,
    validators: ssz.FixedListType(Validator, preset.VALIDATOR_REGISTRY_LIMIT),
    balances: ssz.FixedListType(p.Gwei, preset.VALIDATOR_REGISTRY_LIMIT),
    randao_mixes: ssz.FixedVectorType(p.Bytes32, preset.EPOCHS_PER_HISTORICAL_VECTOR),
    slashings: ssz.FixedVectorType(p.Gwei, preset.EPOCHS_PER_SLASHINGS_VECTOR),
    previous_epoch_participation: ssz.FixedListType(p.Uint8, preset.VALIDATOR_REGISTRY_LIMIT),
    current_epoch_participation: ssz.FixedListType(p.Uint8, preset.VALIDATOR_REGISTRY_LIMIT),
    justification_bits: ssz.BitVectorType(c.JUSTIFICATION_BITS_LENGTH),
    previous_justified_checkpoint: Checkpoint,
    current_justified_checkpoint: Checkpoint,
    finalized_checkpoint: Checkpoint,
    inactivity_scores: ssz.FixedListType(p.Uint64, preset.VALIDATOR_REGISTRY_LIMIT),
    current_sync_committee: SyncCommittee,
    next_sync_committee: SyncCommittee,
    latest_execution_payload_header: ExecutionPayloadHeader,
    next_withdrawal_index: p.WithdrawalIndex,
    next_withdrawal_validator_index: p.ValidatorIndex,
    historical_summaries: ssz.FixedListType(HistoricalSummary, preset.HISTORICAL_ROOTS_LIMIT),
});

pub const SignedBeaconBlock = ssz.VariableContainerType(struct {
    message: BeaconBlock,
    signature: p.BLSSignature,
});
