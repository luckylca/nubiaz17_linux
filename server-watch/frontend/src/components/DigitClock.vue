<script setup lang="ts">
import { computed } from 'vue'

const props = defineProps<{ time: string }>()

// split into individual characters so each digit animates independently
const chars = computed(() => props.time.split('').map((c, i) => ({ c, i })))
</script>

<template>
  <div class="digit-clock" aria-label="current time">
    <span v-for="item in chars" :key="item.i" class="digit-slot">
      <Transition name="digit" mode="out-in">
        <span :key="item.c" class="digit">{{ item.c }}</span>
      </Transition>
    </span>
  </div>
</template>

<style scoped>
.digit-clock {
  display: flex;
  justify-content: center;
  align-items: baseline;
  font-weight: 300;
  line-height: 1;
  letter-spacing: 0.015em;
  color: var(--text-primary);
  text-shadow: 0 0 42px rgba(160, 190, 255, 0.14);
}
.digit-slot {
  display: inline-block;
  min-width: 0.62em;
  text-align: center;
}
.digit {
  display: inline-block;
}

.digit-enter-active {
  transition: transform 280ms var(--ease-out), opacity 280ms var(--ease-out);
}
.digit-leave-active {
  transition: transform 220ms ease-in, opacity 220ms ease-in;
}
.digit-enter-from {
  transform: translateY(0.32em);
  opacity: 0;
}
.digit-leave-to {
  transform: translateY(-0.32em);
  opacity: 0;
}
</style>
