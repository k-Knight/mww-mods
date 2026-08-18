import tkinter as tk
from tkinter import ttk, messagebox
import json
import os

CONFIG_FILE = "script_extender_mod_data_global_settings.json"

INPUT_DISPLAY = [
    "None",
    "A / Cross",
    "B / Circle",
    "X / Square",
    "Y / Triangle",
    "D-Pad Up",
    "D-Pad Down",
    "D-Pad Left",
    "D-Pad Right",
    "LB / L1",
    "RB / R1",
    "LT / L2",
    "RT / R2",
    "LS / L3",
    "RS / R3",
    "Start / Options",
    "Back / Share",
    "Left Thumb Axis",
    "Right Thumb Axis",
    "Left Trigger Axis",
    "Right Trigger Axis",
]

INPUT_SAVE = [
    "None",
    "A",
    "B",
    "X",
    "Y",
    "D-Pad Up",
    "D-Pad Down",
    "D-Pad Left",
    "D-Pad Right",
    "LB",
    "RB",
    "LT",
    "RT",
    "LS",
    "RS",
    "Start",
    "Back",
    "Left Thumb Axis",
    "Right Thumb Axis",
    "Left Trigger Axis",
    "Right Trigger Axis",
]

def get_display_index(save_val):
    try:
        return INPUT_SAVE.index(save_val)
    except ValueError:
        return 0

def get_save_value(display_text):
    try:
        return INPUT_SAVE[INPUT_DISPLAY.index(display_text)]
    except ValueError:
        return "None"

AXIS_OPTIONS = ["None", "Left Thumb Axis", "Right Thumb Axis"]
TRIGGER_AXIS_OPTIONS = ["None", "Left Trigger Axis", "Right Trigger Axis"]

COLORS = {
    "bg": "#121212",
    "surface": "#1e1e1e",
    "surface_light": "#2c2c2c",
    "primary": "#bb86fc",
    "secondary": "#03dac6",
    "error": "#cf6679",
    "fg": "#ffffff",
    "fg_secondary": "#b0b0b0",
    "border": "#333333"
}

class KeyCombinationFrame(ttk.Frame):
    def __init__(self, parent, inputs, on_remove, on_add, on_update, is_first, is_last):
        super().__init__(parent)
        self.configure(style="Surface.TFrame")
        self.inputs = list(inputs)
        self.on_remove = on_remove
        self.on_add = on_add
        self.on_update = on_update
        self.is_first = is_first
        self.is_last = is_last
        self.input_widgets = []
        self.render()

    def render(self):
        for widget in self.winfo_children():
            widget.destroy()
        self.input_widgets = []

        for i, input_val in enumerate(self.inputs):
            input_frame = ttk.Frame(self, style="Surface.TFrame")
            input_frame.pack(side="left", padx=2)

            var = tk.StringVar(value=INPUT_DISPLAY[get_display_index(input_val)])
            combo = ttk.Combobox(input_frame, textvariable=var, values=INPUT_DISPLAY, width=20, state="readonly")
            combo.pack(side="left")
            self.input_widgets.append((input_frame, var, combo))
            var.trace_add("write", lambda *args: self.on_update())

            if i > 0:
                remove_btn = ttk.Button(input_frame, text="✕", width=2, command=lambda idx=i: self.remove_input(idx))
                remove_btn.pack(side="left", padx=2)

        if not self.is_last:
            del_btn = ttk.Button(self, text="🗑 Remove Combo", command=self.on_remove)
            del_btn.pack(side="left", padx=5)
        
        add_btn = ttk.Button(self, text="+ Add Key", command=self.add_input)
        add_btn.pack(side="left", padx=2)

    def add_input(self):
        self.inputs.append("None")
        self.render()
        self.on_add()

    def remove_input(self, index):
        if len(self.inputs) > 1:
            self.inputs.pop(index)
            self.render()
            self.on_add()

    def get_values(self):
        return [get_save_value(var.get()) for _, var, _ in self.input_widgets]


class BindingRow(ttk.Frame):
    def __init__(self, parent, action, binding_type, initial_value, is_axis=False):
        super().__init__(parent)
        self.configure(style="Surface.TFrame")
        self.action = action
        self.binding_type = binding_type
        self.is_axis = is_axis
        self.combo_frames = []
        
        ttk.Label(self, text=action, width=32, anchor="w", style="Title.TLabel").pack(side="left", padx=5, pady=4)
        
        self.container = ttk.Frame(self, style="Surface.TFrame")
        self.container.pack(side="left", fill="x", expand=True)
        
        self.render(initial_value)

    def render(self, initial_value):
        for widget in self.container.winfo_children():
            widget.destroy()
        self.combo_frames = []

        if self.is_axis:
            var = tk.StringVar(value=initial_value if initial_value else "None")
            combo = ttk.Combobox(self.container, textvariable=var, values=AXIS_OPTIONS, width=20, state="readonly")
            combo.pack(side="left", padx=2)
            self.combo_frames.append(("single", var, combo))
        else:
            if self.binding_type == "buttons":
                combinations = initial_value if initial_value else [["None"]]
                for i, combo_inputs in enumerate(combinations):
                    frame = KeyCombinationFrame(
                        self.container,
                        combo_inputs,
                        on_remove=lambda idx=i: self.remove_combo(idx),
                        on_add=self.update_parent,
                        on_update=self.update_parent,
                        is_first=(i==0),
                        is_last=(i==len(combinations)-1)
                    )
                    frame.pack(fill="x", pady=1)
                    self.combo_frames.append(("combo", frame))
                
                add_combo_btn = ttk.Button(self.container, text="+ Add Combination", command=self.add_combo)
                add_combo_btn.pack(pady=3)
            else:
                values = initial_value if initial_value else ["None"]
                for i, val in enumerate(values):
                    row_frame = ttk.Frame(self.container, style="Surface.TFrame")
                    row_frame.pack(fill="x", pady=1)
                    
                    var = tk.StringVar(value=val)
                    combo = ttk.Combobox(row_frame, textvariable=var, values=TRIGGER_AXIS_OPTIONS, width=20, state="readonly")
                    combo.pack(side="left", padx=2)
                    
                    del_btn = ttk.Button(row_frame, text="✕", width=2, command=lambda idx=i: self.remove_trigger(idx))
                    del_btn.pack(side="left", padx=2)
                    
                    self.combo_frames.append(("trigger", var, del_btn))
                
                add_btn = ttk.Button(self.container, text="+ Add Axis", command=self.add_trigger)
                add_btn.pack(pady=3)

    def add_combo(self):
        if self.binding_type == "buttons":
            combos = [f.get_values() for _, f in self.combo_frames]
            combos.append(["None"])
            self.render(combos)
            self.update_parent()

    def remove_combo(self, index):
        if self.binding_type == "buttons":
            combos = [f.get_values() for _, f in self.combo_frames]
            if len(combos) > 1:
                combos.pop(index)
                self.render(combos)
                self.update_parent()

    def add_trigger(self):
        if self.binding_type == "trigger_axis":
            values = [var.get() for _, var, _ in self.combo_frames]
            values.append("None")
            self.render(values)
            self.update_parent()

    def remove_trigger(self, index):
        if self.binding_type == "trigger_axis":
            values = [var.get() for _, var, _ in self.combo_frames]
            if len(values) > 1:
                values.pop(index)
                self.render(values)
                self.update_parent()

    def update_parent(self):
        pass

    def get_value(self):
        if self.is_axis:
            return self.combo_frames[0][1].get()
        elif self.binding_type == "buttons":
            return [f.get_values() for _, f in self.combo_frames]
        else:
            return [var.get() for _, var, _ in self.combo_frames]


class SettingsEditor:
    def __init__(self, root):
        self.root = root
        self.root.title("Gamepad Settings Editor")
        self.root.geometry("1200x800")
        self.root.configure(bg=COLORS["bg"])
        
        self.setup_theme()
        
        self.data = {}
        self.binding_rows = {}
        
        main_container = ttk.Frame(root, style="Bg.TFrame", padding=15)
        main_container.pack(fill="both", expand=True)
        
        canvas = tk.Canvas(main_container, bg=COLORS["bg"], highlightthickness=0)
        scrollbar = ttk.Scrollbar(main_container, orient="vertical", command=canvas.yview)
        self.scrollable_frame = ttk.Frame(canvas, style="Bg.TFrame")
        
        self.scrollable_frame.bind("<Configure>", lambda e: canvas.configure(scrollregion=canvas.bbox("all")))
        canvas.create_window((0, 0), window=self.scrollable_frame, anchor="nw")
        canvas.configure(yscrollcommand=scrollbar.set)
        
        canvas.pack(side="left", fill="both", expand=True)
        scrollbar.pack(side="right", fill="y")

        def _on_mousewheel(event):
            canvas.yview_scroll(int(-1 * (event.delta / 120)), "units")
        canvas.bind_all("<MouseWheel>", _on_mousewheel)

        self.root.update_idletasks() 
        
        btn_frame = ttk.Frame(root, style="Bg.TFrame")
        btn_frame.pack(fill="x", padx=15, pady=10)
        
        load_btn = ttk.Button(btn_frame, text="Load JSON", command=self.load_json)
        load_btn.pack(side="left", padx=5)
        
        save_btn = ttk.Button(btn_frame, text="Save JSON", command=self.save_json)
        save_btn.pack(side="left", padx=5)
        
        self.load_json()

    def setup_theme(self):
        style = ttk.Style()
        style.theme_create('material_black', parent='clam', settings={
            ".": {"configure": {"background": COLORS["bg"], "foreground": COLORS["fg"], "font": ("Segoe UI", 10)}},
            "TFrame": {"configure": {"background": COLORS["bg"]}},
            "Bg.TFrame": {"configure": {"background": COLORS["bg"]}},
            "Surface.TFrame": {"configure": {"background": COLORS["surface"]}},
            "TLabel": {"configure": {"background": COLORS["bg"], "foreground": COLORS["fg"], "font": ("Segoe UI", 10)}},
            "Title.TLabel": {"configure": {"background": COLORS["bg"], "foreground": COLORS["fg"], "font": ("Segoe UI", 10, "bold")}},
            "Section.TLabel": {"configure": {"background": COLORS["bg"], "foreground": COLORS["primary"], "font": ("Segoe UI", 12, "bold")}},
            "TButton": {"configure": {
                "background": COLORS["surface_light"], 
                "foreground": COLORS["fg"], 
                "font": ("Segoe UI", 10, "bold"),
                "bordercolor": COLORS["border"],
                "darkcolor": COLORS["surface_light"],
                "lightcolor": COLORS["surface_light"],
                "focuscolor": COLORS["primary"],
                "padding": (15, 8)
            }},
            "TCombobox": {"configure": {
                "background": COLORS["surface"], 
                "foreground": COLORS["fg"], 
                "fieldbackground": COLORS["surface"],
                "arrowcolor": COLORS["fg"],
                "bordercolor": COLORS["border"],
                "lightcolor": COLORS["surface"],
                "darkcolor": COLORS["surface"],
                "padding": (8, 6)
            }},
            "TCheckbutton": {"configure": {
                "background": COLORS["bg"], 
                "foreground": COLORS["fg"],
                "indicatorbackground": COLORS["surface"],
                "indicatorforeground": COLORS["primary"]
            }},
            "TEntry": {"configure": {
                "background": COLORS["surface"], 
                "foreground": COLORS["fg"],
                "fieldbackground": COLORS["surface"],
                "insertcolor": COLORS["fg"],
                "bordercolor": COLORS["border"],
                "lightcolor": COLORS["surface"],
                "darkcolor": COLORS["surface"],
                "padding": (8, 6)
            }},
            "Vertical.TScrollbar": {"configure": {
                "background": COLORS["surface_light"],
                "troughcolor": COLORS["bg"],
                "bordercolor": COLORS["border"],
                "lightcolor": COLORS["surface_light"],
                "darkcolor": COLORS["surface_light"]
            }}
        })
        style.theme_use('material_black')
        
        self.root.option_add("*TCombobox*Listbox*Background", COLORS["surface"])
        self.root.option_add("*TCombobox*Listbox*Foreground", COLORS["fg"])
        self.root.option_add("*TCombobox*Listbox*Font", ("Segoe UI", 10))

    def load_json(self):
        if not os.path.exists(CONFIG_FILE):
            messagebox.showerror("Error", f"File '{CONFIG_FILE}' not found!")
            return
        
        try:
            with open(CONFIG_FILE, 'r') as f:
                self.data = json.load(f)
            self.build_ui()
        except Exception as e:
            messagebox.showerror("Error", f"Failed to load JSON: {str(e)}")

    def build_ui(self):
        for widget in self.scrollable_frame.winfo_children():
            widget.destroy()
        self.binding_rows = {}
        
        row = 0
        
        ttk.Label(self.scrollable_frame, text="GamepadSupport Settings", style="Section.TLabel").grid(row=row, column=0, columnspan=2, pady=15, sticky="w")
        row += 1
        
        if "GamepadSupport_settings" not in self.data:
            ttk.Label(self.scrollable_frame, text="No GamepadSupport_settings found!", style="TLabel").grid(row=row, column=0, pady=10)
            return
        
        settings = self.data["GamepadSupport_settings"]
        
        for key, value in settings.items():
            if key != "bindings":
                row += 1
                ttk.Label(self.scrollable_frame, text=f"{key}:", style="TLabel").grid(row=row, column=0, padx=5, pady=4, sticky="w")
                
                if isinstance(value, bool):
                    var = tk.BooleanVar(value=value)
                    check = ttk.Checkbutton(self.scrollable_frame, variable=var)
                    check.grid(row=row, column=1, padx=5, pady=4, sticky="w")
                    self.binding_rows[f"setting_{key}"] = ("bool", var)
                elif isinstance(value, (int, float)):
                    var = tk.StringVar(value=str(value))
                    entry = ttk.Entry(self.scrollable_frame, textvariable=var, width=30)
                    entry.grid(row=row, column=1, padx=5, pady=4, sticky="w")
                    self.binding_rows[f"setting_{key}"] = ("number", var)
                elif isinstance(value, str):
                    var = tk.StringVar(value=value)
                    entry = ttk.Entry(self.scrollable_frame, textvariable=var, width=30)
                    entry.grid(row=row, column=1, padx=5, pady=4, sticky="w")
                    self.binding_rows[f"setting_{key}"] = ("string", var)
        
        if "bindings" in settings:
            bindings = settings["bindings"]
            row += 1
            ttk.Label(self.scrollable_frame, text="Button Bindings", style="Section.TLabel").grid(row=row, column=0, columnspan=2, pady=12, sticky="w")
            row += 1
            
            if "buttons" in bindings:
                for action, combinations in bindings["buttons"].items():
                    bind_row = BindingRow(self.scrollable_frame, action, "buttons", combinations)
                    bind_row.grid(row=row, column=0, columnspan=2, sticky="w", pady=1)
                    self.binding_rows[f"buttons_{action}"] = bind_row
                    row += 1
            
            row += 1
            ttk.Label(self.scrollable_frame, text="Trigger Axis Bindings", style="Section.TLabel").grid(row=row, column=0, columnspan=2, pady=12, sticky="w")
            row += 1
            
            if "trigger_axis" in bindings:
                for action, values in bindings["trigger_axis"].items():
                    bind_row = BindingRow(self.scrollable_frame, action, "trigger_axis", values)
                    bind_row.grid(row=row, column=0, columnspan=2, sticky="w", pady=1)
                    self.binding_rows[f"trigger_axis_{action}"] = bind_row
                    row += 1
            
            row += 1
            ttk.Label(self.scrollable_frame, text="Axis Bindings", style="Section.TLabel").grid(row=row, column=0, columnspan=2, pady=12, sticky="w")
            row += 1
            
            if "axis" in bindings:
                for action, value in bindings["axis"].items():
                    bind_row = BindingRow(self.scrollable_frame, action, "axis", value, is_axis=True)
                    bind_row.grid(row=row, column=0, columnspan=2, sticky="w", pady=1)
                    self.binding_rows[f"axis_{action}"] = bind_row
                    row += 1

    def save_json(self):
        if "GamepadSupport_settings" not in self.data:
            messagebox.showerror("Error", "No GamepadSupport_settings to save!")
            return
        
        settings = self.data["GamepadSupport_settings"]
        
        for key, value_info in self.binding_rows.items():
            if key.startswith("setting_"):
                setting_key = key[8:]
                data_type, var = value_info
                if data_type == "bool":
                    settings[setting_key] = var.get()
                elif data_type == "number":
                    try:
                        val = var.get()
                        settings[setting_key] = float(val) if '.' in val else int(val)
                    except:
                        pass
                elif data_type == "string":
                    settings[setting_key] = var.get()
            elif key.startswith("buttons_"):
                action = key[8:]
                if "bindings" in settings and "buttons" in settings["bindings"]:
                    settings["bindings"]["buttons"][action] = value_info.get_value()
            elif key.startswith("trigger_axis_"):
                action = key[13:]
                if "bindings" in settings and "trigger_axis" in settings["bindings"]:
                    settings["bindings"]["trigger_axis"][action] = value_info.get_value()
            elif key.startswith("axis_"):
                action = key[5:]
                if "bindings" in settings and "axis" in settings["bindings"]:
                    settings["bindings"]["axis"][action] = value_info.get_value()

        try:
            def custom_format(data, indent=0):
                ind = "    " * indent
                next_ind = "    " * (indent + 1)
                
                if isinstance(data, dict):
                    if not data: return "{}"
                    items = []
                    for k, v in data.items():
                        items.append(f'{next_ind}"{k}": {custom_format(v, indent + 1)}')
                    return "{\n" + ",\n".join(items) + "\n" + ind + "}"
                
                elif isinstance(data, list):
                    if not data: return "[]"
                    
                    if all(not isinstance(x, (dict, list)) for x in data):
                        formatted_items = [json.dumps(x) for x in data]
                        return "[ " + ", ".join(formatted_items) + " ]"
                    
                    items = []
                    for x in data:
                        items.append(next_ind + custom_format(x, indent + 1))
                    return "[\n" + ",\n".join(items) + "\n" + ind + "]"
                
                else:
                    return json.dumps(data)

            formatted_json = custom_format(self.data)
            
            with open(CONFIG_FILE, 'w') as f:
                f.write(formatted_json)
                
            messagebox.showinfo("Success", "Settings saved successfully!")
        except Exception as e:
            messagebox.showerror("Error", f"Failed to save JSON: {str(e)}")

if __name__ == "__main__":
    root = tk.Tk()
    app = SettingsEditor(root)
    root.mainloop()