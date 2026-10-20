<!--
This component renders the criteria that the server-side Auto-ACMG (SV) service
considers applicable for the currently displayed structural variant.
-->

<script setup lang="ts">
import { computed } from 'vue'

/** Data type used for component's props. */
interface Props {
  /** Auto-ACMG (SV) result as returned by the backend. */
  result?: {
    prediction?: {
      criteria?: Record<string, { prediction?: string }>
    }
  } | null
}

/** Define component's props. */
const props = defineProps<Props>()

/** Applicable criteria, upper-cased, e.g. `["2A", "3A"]`. */
const applicableCriteria = computed((): string[] => {
  const criteria = props.result?.prediction?.criteria ?? {}
  return Object.entries(criteria)
    .filter(([, value]) => value?.prediction === 'applicable')
    .map(([key]) => key.toUpperCase())
})
</script>

<template>
  <div class="d-flex flex-wrap align-center gap-1 mt-1">
    <span class="text-caption font-weight-bold mr-1">Auto-ACMG (SV): </span>
    <template v-if="applicableCriteria.length > 0">
      <span
        v-for="criterion in applicableCriteria"
        :key="criterion"
        class="v-chip v-chip--size-small bg-orange-lighten-4 px-2 mr-1 rounded"
      >
        {{ criterion }}
      </span>
    </template>
    <span v-else class="text-caption text-grey">Ningún criterio aplicable</span>
  </div>
</template>
