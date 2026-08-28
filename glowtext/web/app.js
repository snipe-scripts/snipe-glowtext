const app = document.getElementById('app');
const form = document.getElementById('placement-form');
const placementId = document.getElementById('placement-id');
const textInput = document.getElementById('text');
const textCount = document.getElementById('text-count');
const symbolButtons = document.querySelectorAll('[data-symbol]');
const glyphPreview = document.getElementById('glyph-preview');
const glyphSelectionNote = document.getElementById('glyph-selection-note');
const selectAllGlyphsButton = document.getElementById('select-all-glyphs');
const clearGlyphSelectionButton = document.getElementById('clear-glyph-selection');
const layout = document.getElementById('layout');
const alignment = document.getElementById('alignment');
const scale = document.getElementById('scale');
const scaleLabel = document.getElementById('scale-label');
const spacing = document.getElementById('spacing');
const lineSpacing = document.getElementById('line-spacing');
const lineSpacingLabel = document.getElementById('line-spacing-label');
const lightEnabled = document.getElementById('light-enabled');
const rgbEnabled = document.getElementById('rgb-enabled');
const rgbControls = document.getElementById('rgb-controls');
const rgbFrequency = document.getElementById('rgb-frequency');
const rgbFrequencyValue = document.getElementById('rgb-frequency-value');
const rgbSpread = document.getElementById('rgb-spread');
const rgbSpreadValue = document.getElementById('rgb-spread-value');
const paletteElement = document.getElementById('palette');
const tintName = document.getElementById('tint-name');
const status = document.getElementById('form-status');
const submitButton = document.getElementById('submit');
const saveButton = document.getElementById('save-changes');
const search = document.getElementById('search');
const list = document.getElementById('placement-list');
const emptyState = document.getElementById('empty-state');
const editorHelp = document.getElementById('editor-help');
const cursorLabel = document.getElementById('cursor-label');
const deleteModal = document.getElementById('delete-modal');
const deleteDescription = document.getElementById('delete-description');
const deleteCancel = document.getElementById('delete-cancel');
const deleteConfirm = document.getElementById('delete-confirm');

let records = [];
let palette = [];
let defaults = {};
let limits = { maxGlyphs: 64, maxTextLength: 128 };
let rgbConfig = {
    minFrequency: 0.05,
    maxFrequency: 3,
    minSpread: 0,
    maxSpread: 360,
    palette: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
};
let selectedTint = 0;
let glyphTints = [];
let selectedGlyphIndices = new Set();
let lastSelectedGlyphIndex = null;
let pendingDeleteRecord = null;
let deleteReturnFocus = null;
const supportedPunctuation = new Set([
    '.', ',', '!', '?', "'", '"', ':', ';', '-', '_', '/', '\\',
    '(', ')', '&', '+', '=', '@', '#', '%', '*', '<', '>',
    '←', '→', '↑', '↓',
]);

const post = async (event, data = {}) => {
    const response = await fetch(`https://${GetParentResourceName()}/${event}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data),
    });
    return response.json();
};

const setStatus = (message = '', kind = '') => {
    status.textContent = message;
    status.className = `status ${kind}`;
};

const visibleCharacters = () => [...textInput.value].filter((character) => !/\s/.test(character));
const visibleGlyphCount = () => visibleCharacters().length;
const visibleCountIn = (value) => [...value].filter((character) => !/\s/.test(character)).length;

const updateCount = () => {
    const count = visibleGlyphCount();
    textCount.textContent = `${count} / ${limits.maxGlyphs} glyphs`;
    textCount.style.color = count > limits.maxGlyphs ? '#ef8585' : '';
};

const updateRgbControlState = () => {
    const enabled = rgbEnabled.checked;
    rgbFrequency.disabled = !enabled;
    rgbSpread.disabled = !enabled;
    rgbControls.classList.toggle('disabled', !enabled);
};

const updateRgbControlValues = () => {
    rgbFrequencyValue.textContent = `${Number(rgbFrequency.value).toFixed(2)} Hz`;
    rgbSpreadValue.textContent = `${Math.round(Number(rgbSpread.value))}°`;
};

const configureRgbControls = () => {
    rgbFrequency.min = String(rgbConfig.minFrequency ?? 0.05);
    rgbFrequency.max = String(rgbConfig.maxFrequency ?? 3);
    rgbSpread.min = String(rgbConfig.minSpread ?? 0);
    rgbSpread.max = String(rgbConfig.maxSpread ?? 360);
};

const rgbTintForGlyph = (glyphIndex, timeMs = performance.now()) => {
    const rgbPalette = Array.isArray(rgbConfig.palette) && rgbConfig.palette.length
        ? rgbConfig.palette
        : [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];
    const frequency = Number(rgbFrequency.value) || Number(defaults.rgbFrequency) || 0.5;
    const spread = Number(rgbSpread.value) || 0;
    const cycle = ((timeMs / 1000) * frequency) + ((glyphIndex * spread) / 360);
    return rgbPalette[Math.floor((((cycle % 1) + 1) % 1) * rgbPalette.length)];
};

const updateRgbPreview = (timeMs = performance.now()) => {
    if (!rgbEnabled.checked) return;
    glyphPreview.querySelectorAll('.preview-glyph').forEach((button) => {
        const glyphIndex = Number(button.dataset.glyphIndex);
        const tint = palette[rgbTintForGlyph(glyphIndex, timeMs)] ?? palette[0];
        button.style.color = tint?.hex ?? '#ffffff';
    });
};

const updateGlyphSelectionNote = (characters) => {
    const selectedCount = selectedGlyphIndices.size;
    if (!characters.length) {
        glyphSelectionNote.textContent = 'No visible characters';
    } else if (selectedCount === characters.length) {
        glyphSelectionNote.textContent = `All ${characters.length} characters selected`;
    } else if (selectedCount === 1) {
        const [index] = selectedGlyphIndices;
        glyphSelectionNote.textContent = `“${characters[index]}” selected · character ${index + 1} of ${characters.length}`;
    } else {
        glyphSelectionNote.textContent = selectedCount ? `${selectedCount} characters selected` : 'No characters selected';
    }
    selectAllGlyphsButton.disabled = !characters.length || selectedCount === characters.length;
    clearGlyphSelectionButton.disabled = selectedCount === 0;
};

const paintPaletteSelection = (tintIndex, label) => {
    [...paletteElement.children].forEach((element, elementIndex) => {
        const matches = tintIndex !== null && elementIndex === tintIndex;
        element.classList.toggle('selected', matches);
        element.setAttribute('aria-checked', matches ? 'true' : 'false');
    });
    tintName.textContent = label;
};

const syncPaletteToGlyphSelection = () => {
    const indices = [...selectedGlyphIndices];
    if (!indices.length) {
        paintPaletteSelection(null, 'No selection');
        return;
    }

    const firstTint = Number(glyphTints[indices[0]]) || 0;
    const hasMixedTints = indices.some((index) => (Number(glyphTints[index]) || 0) !== firstTint);
    if (hasMixedTints) {
        paintPaletteSelection(null, 'Mixed');
        return;
    }

    selectedTint = firstTint;
    paintPaletteSelection(firstTint, palette[firstTint]?.name ?? `Tint ${firstTint}`);
};

const renderGlyphPreview = () => {
    const characters = visibleCharacters();
    const isVertical = layout.value === 'vertical';
    const lines = textInput.value.replace(/\r/g, '').split('\n');
    glyphPreview.classList.toggle('vertical', isVertical);
    glyphPreview.classList.toggle('multiline', lines.length > 1);
    lineSpacingLabel.textContent = isVertical ? 'Column spacing' : 'Line spacing';
    glyphPreview.replaceChildren();
    let glyphIndex = 0;
    const rgbTime = performance.now();
    lines.forEach((line) => {
        const lineElement = document.createElement('div');
        lineElement.className = 'preview-line';
        lineElement.classList.toggle('empty', line.length === 0);
        lineElement.setAttribute('role', 'presentation');

        [...line].forEach((character) => {
            if (/\s/.test(character)) {
                const spacer = document.createElement('span');
                spacer.className = 'preview-space';
                spacer.setAttribute('aria-hidden', 'true');
                lineElement.appendChild(spacer);
                return;
            }

            const index = glyphIndex;
            glyphIndex += 1;
            const button = document.createElement('button');
            const tintIndex = rgbEnabled.checked ? rgbTintForGlyph(index, rgbTime) : glyphTints[index];
            const tint = palette[tintIndex] ?? palette[0];
            button.type = 'button';
            button.className = 'preview-glyph';
            button.textContent = character;
            button.dataset.glyphIndex = String(index);
            button.title = `Character ${index + 1}: ${character}`;
            button.style.color = tint?.hex ?? '#ffffff';
            button.classList.toggle('selected', selectedGlyphIndices.has(index));
            button.classList.toggle('glowing', lightEnabled.checked);
            button.setAttribute('role', 'option');
            button.setAttribute('aria-selected', selectedGlyphIndices.has(index) ? 'true' : 'false');
            button.addEventListener('click', (event) => {
                if (event.shiftKey && lastSelectedGlyphIndex !== null) {
                    if (!event.ctrlKey && !event.metaKey) selectedGlyphIndices.clear();
                    const start = Math.min(lastSelectedGlyphIndex, index);
                    const end = Math.max(lastSelectedGlyphIndex, index);
                    for (let selectedIndex = start; selectedIndex <= end; selectedIndex += 1) {
                        selectedGlyphIndices.add(selectedIndex);
                    }
                } else if (event.ctrlKey || event.metaKey) {
                    if (selectedGlyphIndices.has(index)) selectedGlyphIndices.delete(index);
                    else selectedGlyphIndices.add(index);
                } else {
                    selectedGlyphIndices = new Set([index]);
                }
                lastSelectedGlyphIndex = index;
                renderGlyphPreview();
            });
            lineElement.appendChild(button);
        });
        glyphPreview.appendChild(lineElement);
    });
    updateGlyphSelectionNote(characters);
    syncPaletteToGlyphSelection();
};

const selectAllGlyphs = () => {
    selectedGlyphIndices = new Set(visibleCharacters().map((_, index) => index));
    lastSelectedGlyphIndex = selectedGlyphIndices.size ? 0 : null;
    renderGlyphPreview();
};

const syncGlyphTints = () => {
    const characters = visibleCharacters();
    const previousCount = glyphTints.length;
    const hadAllSelected = previousCount > 0 && selectedGlyphIndices.size === previousCount;
    glyphTints = characters.map((_, index) => Number.isInteger(glyphTints[index]) ? glyphTints[index] : selectedTint);
    selectedGlyphIndices = new Set([...selectedGlyphIndices].filter((index) => index < characters.length));
    if (hadAllSelected || (previousCount === 0 && characters.length)) {
        selectedGlyphIndices = new Set(characters.map((_, index) => index));
    }
    renderGlyphPreview();
};

const insertSymbol = (symbol) => {
    const currentValue = textInput.value;
    const start = textInput.selectionStart ?? currentValue.length;
    const end = textInput.selectionEnd ?? start;
    const nextValue = `${currentValue.slice(0, start)}${symbol}${currentValue.slice(end)}`;

    if ([...nextValue].length > limits.maxTextLength) {
        setStatus(`Text is limited to ${limits.maxTextLength} characters.`, 'error');
        textInput.focus();
        return;
    }

    const glyphIndex = visibleCountIn(currentValue.slice(0, start));
    const replacedGlyphCount = visibleCountIn(currentValue.slice(start, end));
    glyphTints.splice(glyphIndex, replacedGlyphCount, selectedTint);
    textInput.value = nextValue;
    textInput.setSelectionRange(start + symbol.length, start + symbol.length);
    selectedGlyphIndices = new Set([glyphIndex]);
    lastSelectedGlyphIndex = glyphIndex;
    setStatus();
    updateCount();
    renderGlyphPreview();
    textInput.focus();
};

const selectTint = (index, applyToSelection = false) => {
    selectedTint = Number(index) || 0;
    paintPaletteSelection(selectedTint, palette[selectedTint]?.name ?? `Tint ${selectedTint}`);
    if (applyToSelection) {
        if (!selectedGlyphIndices.size) {
            setStatus('Select one or more characters first.', 'error');
            syncPaletteToGlyphSelection();
            return;
        }
        selectedGlyphIndices.forEach((glyphIndex) => { glyphTints[glyphIndex] = selectedTint; });
        setStatus();
        renderGlyphPreview();
    }
};

const renderPalette = () => {
    paletteElement.replaceChildren();
    palette.forEach((item, index) => {
        const button = document.createElement('button');
        button.type = 'button';
        button.className = 'swatch';
        button.style.background = item.hex;
        button.title = `${index}: ${item.name}`;
        button.setAttribute('role', 'radio');
        button.addEventListener('click', () => selectTint(index, true));
        paletteElement.appendChild(button);
    });
    selectTint(selectedTint, false);
};

const resetForm = () => {
    placementId.value = '';
    textInput.value = defaults.text ?? 'Glow';
    layout.value = defaults.layout ?? 'horizontal';
    alignment.value = defaults.alignment ?? 'center';
    scale.value = defaults.scale ?? 1;
    spacing.value = defaults.spacing ?? 0.08;
    lineSpacing.value = defaults.lineSpacing ?? 0.2;
    lightEnabled.checked = defaults.lightEnabled !== false;
    rgbEnabled.checked = defaults.rgbEnabled === true;
    rgbFrequency.value = defaults.rgbFrequency ?? 0.5;
    rgbSpread.value = defaults.rgbSpread ?? 30;
    updateRgbControlState();
    updateRgbControlValues();
    scale.disabled = false;
    scaleLabel.textContent = 'Starting size';
    saveButton.hidden = true;
    submitButton.textContent = 'Place with gizmo';
    selectTint(defaults.tint ?? 0, false);
    glyphTints = visibleCharacters().map(() => selectedTint);
    selectAllGlyphs();
    setStatus();
    updateCount();
};

const loadRecord = (record) => {
    placementId.value = record.id;
    textInput.value = record.text;
    layout.value = record.layout;
    alignment.value = record.alignment;
    const matrix = record.matrix ?? [];
    scale.value = Math.hypot(Number(matrix[0] ?? 1), Number(matrix[1] ?? 0), Number(matrix[2] ?? 0)).toFixed(2);
    scale.disabled = true;
    scaleLabel.textContent = 'Current size';
    spacing.value = record.spacing;
    lineSpacing.value = record.lineSpacing;
    lightEnabled.checked = record.lightEnabled;
    rgbEnabled.checked = record.rgbEnabled === true;
    rgbFrequency.value = record.rgbFrequency ?? defaults.rgbFrequency ?? 0.5;
    rgbSpread.value = record.rgbSpread ?? defaults.rgbSpread ?? 30;
    updateRgbControlState();
    updateRgbControlValues();
    selectTint(record.tint, false);
    const characters = visibleCharacters();
    glyphTints = Array.isArray(record.glyphTints) && record.glyphTints.length === characters.length
        ? record.glyphTints.map((value) => Math.max(0, Math.min(palette.length - 1, Number(value) || 0)))
        : characters.map(() => selectedTint);
    selectAllGlyphs();
    saveButton.hidden = false;
    submitButton.textContent = 'Update with gizmo';
    setStatus(`Editing placement #${record.id}.`, 'success');
    updateCount();
    textInput.focus();
};

const closeDeleteModal = () => {
    deleteModal.hidden = true;
    pendingDeleteRecord = null;
    deleteConfirm.disabled = false;
    deleteReturnFocus?.focus();
    deleteReturnFocus = null;
};

const openDeleteModal = (record, trigger) => {
    pendingDeleteRecord = record;
    deleteReturnFocus = trigger;
    deleteDescription.textContent = `Placement #${record.id} will be permanently removed.`;
    deleteModal.hidden = false;
    deleteCancel.focus();
};

const renderRecords = () => {
    const query = search.value.trim().toLowerCase();
    const filtered = records.filter((record) => !query || record.text.toLowerCase().includes(query) || String(record.id).includes(query));
    list.replaceChildren();
    emptyState.style.display = filtered.length ? 'none' : 'block';

    filtered.forEach((record) => {
        const row = document.createElement('div');
        row.className = 'placement-row';

        const id = document.createElement('div');
        id.className = 'placement-id';
        id.textContent = `#${record.id}`;

        const details = document.createElement('div');
        const placementText = document.createElement('div');
        placementText.className = 'placement-text';
        placementText.textContent = record.text.replace(/\n/g, ' ↵ ');
        const meta = document.createElement('div');
        meta.className = 'placement-meta';
        const matrix = record.matrix ?? [];
        meta.textContent = `${record.layout} · ${Number(matrix[9] ?? 0).toFixed(1)}, ${Number(matrix[10] ?? 0).toFixed(1)}, ${Number(matrix[11] ?? 0).toFixed(1)}`;
        details.append(placementText, meta);

        const actions = document.createElement('div');
        actions.className = 'row-actions';
        const edit = document.createElement('button');
        edit.type = 'button';
        edit.className = 'row-button';
        edit.textContent = 'Edit';
        edit.addEventListener('click', () => loadRecord(record));
        const remove = document.createElement('button');
        remove.type = 'button';
        remove.className = 'row-button danger';
        remove.textContent = 'Delete';
        remove.addEventListener('click', () => openDeleteModal(record, remove));
        actions.append(edit, remove);
        row.append(id, details, actions);
        list.appendChild(row);
    });
};

const placementPayload = () => {
    const text = textInput.value.replace(/\r/g, '');
    const count = visibleGlyphCount();
    const unsupported = [...text].some((character) => !/[A-Za-z0-9 \n]/.test(character) && !supportedPunctuation.has(character));
    if (!text || unsupported) {
        return { error: 'The text contains an unsupported character.' };
    }
    if (count < 1 || count > limits.maxGlyphs) {
        return { error: `Use between 1 and ${limits.maxGlyphs} visible glyphs.` };
    }

    return { data: {
        id: placementId.value || null,
        text,
        layout: layout.value,
        alignment: alignment.value,
        scale: Number(scale.value),
        spacing: Number(spacing.value),
        lineSpacing: Number(lineSpacing.value),
        tint: selectedTint,
        glyphTints: [...glyphTints],
        lightEnabled: lightEnabled.checked,
        rgbEnabled: rgbEnabled.checked,
        rgbFrequency: Number(rgbFrequency.value),
        rgbSpread: Number(rgbSpread.value),
    } };
};

form.addEventListener('submit', async (event) => {
    event.preventDefault();
    const payload = placementPayload();
    if (payload.error) {
        setStatus(payload.error, 'error');
        return;
    }

    const result = await post('startPlacement', payload.data);
    if (!result.ok) setStatus(result.error ?? 'Could not start placement.', 'error');
});

saveButton.addEventListener('click', async () => {
    const payload = placementPayload();
    if (payload.error) {
        setStatus(payload.error, 'error');
        return;
    }
    if (!placementId.value) {
        setStatus('Select an existing placement first.', 'error');
        return;
    }

    saveButton.disabled = true;
    const result = await post('saveChanges', payload.data);
    saveButton.disabled = false;
    if (!result.ok) {
        setStatus(result.error ?? 'Could not save changes.', 'error');
        return;
    }
    setStatus(`Saving placement #${placementId.value}…`, 'success');
});

deleteCancel.addEventListener('click', closeDeleteModal);
deleteModal.addEventListener('click', (event) => {
    if (event.target === deleteModal) closeDeleteModal();
});
deleteConfirm.addEventListener('click', async () => {
    if (!pendingDeleteRecord) return;
    deleteConfirm.disabled = true;
    const result = await post('deletePlacement', { id: pendingDeleteRecord.id });
    if (!result.ok) {
        setStatus(result.error ?? 'Delete failed.', 'error');
        deleteConfirm.disabled = false;
        return;
    }
    closeDeleteModal();
});

document.getElementById('close').addEventListener('click', () => post('close'));
document.getElementById('reset').addEventListener('click', resetForm);
selectAllGlyphsButton.addEventListener('click', selectAllGlyphs);
clearGlyphSelectionButton.addEventListener('click', () => {
    selectedGlyphIndices.clear();
    lastSelectedGlyphIndex = null;
    renderGlyphPreview();
});
symbolButtons.forEach((button) => {
    button.addEventListener('mousedown', (event) => event.preventDefault());
    button.addEventListener('click', () => insertSymbol(button.dataset.symbol));
});
textInput.addEventListener('input', () => {
    updateCount();
    syncGlyphTints();
});
lightEnabled.addEventListener('change', renderGlyphPreview);
rgbEnabled.addEventListener('change', () => {
    updateRgbControlState();
    renderGlyphPreview();
});
rgbFrequency.addEventListener('input', () => {
    updateRgbControlValues();
    updateRgbPreview();
});
rgbSpread.addEventListener('input', () => {
    updateRgbControlValues();
    updateRgbPreview();
});
layout.addEventListener('change', renderGlyphPreview);
search.addEventListener('input', renderRecords);

window.addEventListener('keydown', (event) => {
    if (app.hidden) return;
    if (event.key === 'Tab' && !deleteModal.hidden) {
        event.preventDefault();
        (document.activeElement === deleteCancel ? deleteConfirm : deleteCancel).focus();
        return;
    }
    if (event.key !== 'Escape') return;
    if (!deleteModal.hidden) {
        event.preventDefault();
        closeDeleteModal();
        return;
    }
    post('close');
});

window.addEventListener('message', ({ data }) => {
    if (data.action === 'open') {
        records = data.records ?? [];
        palette = data.palette ?? [];
        defaults = data.defaults ?? {};
        limits = data.limits ?? limits;
        rgbConfig = data.rgbEffect ?? rgbConfig;
        configureRgbControls();
        selectedTint = defaults.tint ?? 0;
        renderPalette();
        resetForm();
        renderRecords();
        app.hidden = false;
        textInput.focus();
    }
    if (data.action === 'close') {
        if (!deleteModal.hidden) closeDeleteModal();
        app.hidden = true;
    }
    if (data.action === 'records') {
        records = data.records ?? [];
        renderRecords();
    }
    if (data.action === 'notify') setStatus(data.message ?? '', data.kind ?? '');
    if (data.action === 'editor') editorHelp.hidden = !data.visible;
    if (data.action === 'cursorMode') cursorLabel.textContent = data.enabled ? 'Camera mode' : 'Gizmo mode';
});

setInterval(() => {
    if (!app.hidden && rgbEnabled.checked) updateRgbPreview();
}, 50);

// The document canvas must stay transparent; only explicitly opened panels paint UI.
document.documentElement.classList.remove('nui-loading');
