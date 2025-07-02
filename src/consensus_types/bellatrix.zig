const std = @import("std");
const ssz = @import("ssz");
const p = @import("primitive.zig");
const c = @import("constants.zig");
const preset = @import("preset.zig").active_preset;
const phase0 = @import("phase0.zig");
const altair = @import("altair.zig");

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

pub const SyncAggregate = altair.SyncAggregate;
pub const SyncCommittee = altair.SyncCommittee;
pub const SyncCommitteeMessage = altair.SyncCommitteeMessage;
pub const SyncCommitteeContribution = altair.SyncCommitteeContribution;
pub const ContributionAndProof = altair.ContributionAndProof;
pub const SignedContributionAndProof = altair.SignedContributionAndProof;
pub const SyncAggregatorSelectionData = altair.SyncAggregatorSelectionData;
pub const LightClientHeader = altair.LightClientHeader;
pub const LightClientBootstrap = altair.LightClientBootstrap;
pub const LightClientUpdate = altair.LightClientUpdate;
pub const LightClientFinalityUpdate = altair.LightClientFinalityUpdate;
pub const LightClientOptimisticUpdate = altair.LightClientOptimisticUpdate;

pub const ExecutionPayload = ssz.VariableContainerType(struct {
    parent_hash: p.Bytes32,
    fee_recipient: p.ExecutionAddress,
    state_root: p.Bytes32,
    receipts_root: p.Bytes32,
    logs_bloom: ssz.ByteVectorType(preset.BYTES_PER_LOGS_BLOOM),
    prev_randao: p.Bytes32,
    block_number: p.Uint64,
    gas_limit: p.Uint64,
    gas_used: p.Uint64,
    timestamp: p.Uint64,
    extra_data: ssz.ByteListType(preset.MAX_EXTRA_DATA_BYTES),
    base_fee_per_gas: p.Uint256,
    block_hash: p.Bytes32,
    transactions: ssz.VariableListType(ssz.ByteListType(preset.MAX_BYTES_PER_TRANSACTION), preset.MAX_TRANSACTIONS_PER_PAYLOAD),
});

pub const ExecutionPayloadHeader = ssz.VariableContainerType(struct {
    parent_hash: p.Bytes32,
    fee_recipient: p.ExecutionAddress,
    state_root: p.Bytes32,
    receipts_root: p.Bytes32,
    logs_bloom: ssz.ByteVectorType(preset.BYTES_PER_LOGS_BLOOM),
    prev_randao: p.Bytes32,
    block_number: p.Uint64,
    gas_limit: p.Uint64,
    gas_used: p.Uint64,
    timestamp: p.Uint64,
    extra_data: ssz.ByteListType(preset.MAX_EXTRA_DATA_BYTES),
    base_fee_per_gas: p.Uint256,
    block_hash: p.Bytes32,
    transactions_root: p.Root,
});

pub const PowBlock = ssz.FixedContainerType(struct {
    block_hash: p.Bytes32,
    parent_hash: p.Bytes32,
    total_difficulty: p.Uint256,
});

pub const BeaconBlockBody = ssz.VariableContainerType(struct {
    randao_reveal: p.BLSSignature,
    eth1_data: Eth1Data,
    graffiti: p.Bytes32,
    proposer_slashings: ProposerSlashings,
    attester_slashings: AttesterSlashings,
    attestations: Attestations,
    deposits: ssz.FixedListType(Deposit, preset.MAX_DEPOSITS),
    voluntary_exits: ssz.FixedListType(SignedVoluntaryExit, preset.MAX_VOLUNTARY_EXITS),
    sync_aggregate: SyncAggregate,
    execution_payload: ExecutionPayload,
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
});

pub const SignedBeaconBlock = ssz.VariableContainerType(struct {
    message: BeaconBlock,
    signature: p.BLSSignature,
});
