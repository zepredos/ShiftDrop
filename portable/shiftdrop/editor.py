from __future__ import annotations

import json
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageQt, ExifTags
from PySide6.QtCore import Qt, QPointF, QRectF, Signal, QTimer
from PySide6.QtGui import QColor, QFont, QPainter, QPainterPath, QPen, QPixmap
from PySide6.QtWidgets import (QWidget, QLabel, QPushButton, QVBoxLayout, QHBoxLayout, QSlider,
    QSpinBox, QComboBox, QTextEdit, QColorDialog, QMessageBox)

from .engine import PALETTES, add_background, adjust_image, crop_image
from .wheel import EMBER, INK

TITLES = {'CROP': 'Crop Image', 'ADD BG': 'Add BG', 'COMPRESS': 'Compress Image', 'METADATA': 'Metadata',
          'EDIT': 'Edit Image', 'ANNOTATE': 'Annotate Image', 'REDACT': 'Redact Image'}
STYLE = '''
QWidget { color:#392819; font-family:Sans Serif; font-size:11px; }
QPushButton { border:0; border-radius:5px; padding:5px 9px; background:rgba(110,74,45,12); }
QPushButton:hover { background:rgba(110,74,45,27); }
QPushButton:checked, QPushButton#primary { background:#ed3d0e; color:white; }
QPushButton:focus { border:1px solid #ed3d0e; }
QSpinBox, QComboBox, QTextEdit { background:rgba(255,255,255,185); border:1px solid rgba(70,45,25,20); border-radius:4px; padding:3px; }
QSlider::groove:horizontal { background:rgba(80,65,50,35); height:4px; border-radius:2px; }
QSlider::sub-page:horizontal { background:#ed3d0e; border-radius:2px; }
QSlider::handle:horizontal { background:white; width:18px; height:18px; margin:-7px 0; border-radius:9px; }
'''


def pixmap(image):
    return QPixmap.fromImage(ImageQt.ImageQt(image.convert('RGBA')).copy())


class GlassWindow(QWidget):
    def __init__(self, title, height=654):
        super().__init__(None, Qt.WindowType.Tool | Qt.WindowType.FramelessWindowHint)
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground)
        self.setWindowTitle('ShiftDrop · ' + title)
        self.setStyleSheet(STYLE)
        self.setFixedSize(460, height)
        self.layout = QVBoxLayout(self)
        self.layout.setContentsMargins(20, 0, 20, 12)
        self.layout.setSpacing(0)
        header = QHBoxLayout()
        close = QPushButton('×'); close.setAccessibleName('Close editor'); close.setFixedSize(25, 25); close.clicked.connect(self.close)
        header.addWidget(close); header.addStretch()
        heading = QLabel(title); heading.setFont(QFont('Sans Serif', 11, QFont.Weight.DemiBold))
        header.addWidget(heading); header.addStretch(); header.addSpacing(25)
        self.layout.addLayout(header)
        header.setContentsMargins(0, 12, 0, 12)
        self._drag_offset = None

    def paintEvent(self, event):
        painter = QPainter(self); painter.setRenderHint(QPainter.RenderHint.Antialiasing)
        painter.setBrush(QColor(242, 218, 194, 238)); painter.setPen(QPen(QColor(255,255,255,160), .8))
        painter.drawRoundedRect(QRectF(.5,.5,self.width()-1,self.height()-1),22,22)
        painter.setPen(QColor(110,80,55,35)); painter.drawLine(1,47,self.width()-1,47)

    def keyPressEvent(self, event):
        if event.key() == Qt.Key.Key_Escape:
            self.close()
        else:
            super().keyPressEvent(event)

    def mousePressEvent(self, event):
        if event.position().y() < 46 and event.button() == Qt.MouseButton.LeftButton:
            if self.windowHandle():
                self.windowHandle().startSystemMove()


class ImageCanvas(QWidget):
    changed = Signal()

    def __init__(self, image, tool):
        super().__init__()
        self.image = image
        self.preview = pixmap(image)
        self.tool = tool
        self.crop = (0., 0., 1., 1.)
        self.ratio = None
        self.strokes, self.redactions = [], []
        self._initial = None
        self._handle = None
        self.setMinimumHeight(316)
        self.setMouseTracking(True)
        self.setAccessibleName('Image crop and drawing canvas' if tool in ('CROP','ANNOTATE','REDACT') else 'Image preview')

    def image_rect(self):
        width, height = self.preview.width(), self.preview.height()
        scale = min(self.width()/width, self.height()/height)
        return QRectF((self.width()-width*scale)/2,(self.height()-height*scale)/2,width*scale,height*scale)

    def selection_rect(self):
        rect = self.image_rect(); x,y,w,h = self.crop
        return QRectF(rect.x()+x*rect.width(),rect.y()+y*rect.height(),w*rect.width(),h*rect.height())

    @staticmethod
    def handles(rect):
        return [rect.topLeft(),QPointF(rect.center().x(),rect.top()),rect.topRight(),QPointF(rect.right(),rect.center().y()),
                rect.bottomRight(),QPointF(rect.center().x(),rect.bottom()),rect.bottomLeft(),QPointF(rect.left(),rect.center().y())]

    def normalized(self, point):
        rect = self.image_rect()
        return (min(1,max(0,(point.x()-rect.x())/rect.width())), min(1,max(0,(point.y()-rect.y())/rect.height())))

    def set_crop(self, box):
        x,y,w,h = box
        w,h = max(.001,min(1,w)),max(.001,min(1,h))
        x,y = max(0,min(1-w,x)),max(0,min(1-h,y))
        if self.ratio:
            normalized = self.ratio*self.image.height/self.image.width
            h = min(1-y,w/normalized); w = h*normalized
        self.crop = (x,y,w,h)
        self.changed.emit(); self.update()

    def paintEvent(self, event):
        painter = QPainter(self); painter.setRenderHint(QPainter.RenderHint.Antialiasing)
        rect = self.image_rect(); painter.drawPixmap(rect,self.preview,QRectF(self.preview.rect()))
        if self.tool == 'CROP':
            selection = self.selection_rect()
            outer = QPainterPath(); outer.addRect(rect)
            inner = QPainterPath(); inner.addRect(selection)
            painter.fillPath(outer.subtracted(inner),QColor(0,0,0,140))
            painter.setPen(QPen(EMBER,1.5)); painter.drawRect(selection)
            painter.setPen(QColor(255,255,255,80))
            for factor in (1/3,2/3):
                painter.drawLine(QPointF(selection.x()+selection.width()*factor,selection.top()),QPointF(selection.x()+selection.width()*factor,selection.bottom()))
                painter.drawLine(QPointF(selection.left(),selection.y()+selection.height()*factor),QPointF(selection.right(),selection.y()+selection.height()*factor))
            painter.setPen(Qt.PenStyle.NoPen); painter.setBrush(EMBER)
            for point in self.handles(selection):
                painter.drawRoundedRect(QRectF(point.x()-4,point.y()-4,8,8),1,1)
        elif self.tool in ('ANNOTATE','REDACT'):
            painter.setPen(QPen(EMBER,3,Qt.PenStyle.SolidLine,Qt.PenCapStyle.RoundCap,Qt.PenJoinStyle.RoundJoin))
            for stroke in self.strokes:
                path = QPainterPath()
                for index,(x,y) in enumerate(stroke):
                    point = QPointF(rect.x()+x*rect.width(),rect.y()+y*rect.height())
                    path.moveTo(point) if not index else path.lineTo(point)
                painter.drawPath(path)
            for x,y,w,h in self.redactions:
                painter.fillRect(QRectF(rect.x()+x*rect.width(),rect.y()+y*rect.height(),w*rect.width(),h*rect.height()),Qt.GlobalColor.black)

    def mousePressEvent(self, event):
        if event.button() != Qt.MouseButton.LeftButton:
            return
        self._start = event.position()
        self._initial = self.crop
        if self.tool == 'CROP':
            selection = self.selection_rect(); points = self.handles(selection)
            nearest = min(range(8),key=lambda i: math.hypot(points[i].x()-event.position().x(),points[i].y()-event.position().y()))
            self._handle = nearest if math.hypot(points[nearest].x()-event.position().x(),points[nearest].y()-event.position().y()) < 16 else 8 if selection.contains(event.position()) else 9
        elif self.tool == 'ANNOTATE':
            self.strokes.append([self.normalized(event.position())])
        elif self.tool == 'REDACT':
            x,y = self.normalized(event.position()); self.redactions.append((x,y,0,0))

    def mouseMoveEvent(self, event):
        if self._initial is None or not event.buttons() & Qt.MouseButton.LeftButton:
            return
        rect = self.image_rect()
        if self.tool == 'CROP':
            x,y,w,h = self._initial
            dx,dy = (event.position().x()-self._start.x())/rect.width(),(event.position().y()-self._start.y())/rect.height()
            if self._handle == 8:
                self.set_crop((x+dx,y+dy,w,h)); return
            if self._handle == 9:
                x0,y0 = self.normalized(self._start); x1,y1 = self.normalized(event.position())
                self.set_crop((min(x0,x1),min(y0,y1),max(.001,abs(x1-x0)),max(.001,abs(y1-y0)))); return
            x1,y1 = x+w,y+h
            if self._handle in (0,6,7): x = min(x1-.001,max(0,x+dx))
            if self._handle in (2,3,4): x1 = max(x+.001,min(1,x1+dx))
            if self._handle in (0,1,2): y = min(y1-.001,max(0,y+dy))
            if self._handle in (4,5,6): y1 = max(y+.001,min(1,y1+dy))
            self.set_crop((x,y,x1-x,y1-y))
        elif self.tool == 'ANNOTATE' and self.strokes:
            self.strokes[-1].append(self.normalized(event.position())); self.update()
        elif self.tool == 'REDACT' and self.redactions:
            x0,y0 = self.normalized(self._start); x1,y1 = self.normalized(event.position())
            self.redactions[-1] = (min(x0,x1),min(y0,y1),abs(x1-x0),abs(y1-y0)); self.update()

    def mouseReleaseEvent(self, event):
        self._initial = None

    def flattened(self):
        result = self.image.copy().convert('RGBA'); draw = ImageDraw.Draw(result)
        for stroke in self.strokes:
            points = [(round(x*result.width),round(y*result.height)) for x,y in stroke]
            if len(points)>1:
                draw.line(points,fill='#ed3d0e',width=max(2,round(3*result.width/max(1,self.image_rect().width()))),joint='curve')
        for x,y,w,h in self.redactions:
            draw.rectangle((round(x*result.width),round(y*result.height),round((x+w)*result.width),round((y+h)*result.height)),fill='black')
        result.info.clear()
        return result


class Editor(GlassWindow):
    saved = Signal(object,str,str,float)

    def __init__(self, tool, source: Path, image):
        super().__init__(TITLES[tool],656 if tool=='ADD BG' else 654)
        self.tool,self.source,self.image = tool,source,image
        self.values = {}; self.swatches=[]; self.ratio_buttons=[]
        self.palette=0; self.ratio=None; self.rotation=0; self.flipped=False
        self.preview_timer=QTimer(self); self.preview_timer.setSingleShot(True); self.preview_timer.setInterval(40); self.preview_timer.timeout.connect(self.update_preview)
        self.layout.addSpacing(20)
        self.canvas=ImageCanvas(image,tool); self.canvas.setFixedHeight(410 if tool in ('CROP','ANNOTATE','REDACT') else 316 if tool=='ADD BG' else 370)
        if tool=='METADATA':
            info={'File':str(source),'Dimensions':f'{image.width} × {image.height}','Size':source.stat().st_size}
            with Image.open(source) as original:
                info.update({ExifTags.TAGS.get(key,str(key)):str(value) for key,value in original.getexif().items()})
            metadata=QTextEdit(); metadata.setReadOnly(True); metadata.setPlainText(json.dumps(info,ensure_ascii=False,indent=2)); self.layout.addWidget(metadata)
        else:
            self.layout.addWidget(self.canvas); self.layout.addSpacing(18); self.make_controls()
        self.layout.addStretch()
        footer=QHBoxLayout(); reset=QPushButton('Reset'); reset.clicked.connect(self.reset)
        if tool!='METADATA': footer.addWidget(reset)
        footer.addStretch()
        save=QPushButton('Done' if tool=='METADATA' else 'Save with Background' if tool=='ADD BG' else 'Apply' if tool=='CROP' else 'Save Copy')
        save.setObjectName('primary'); save.clicked.connect(self.save); footer.addWidget(save)
        self.layout.addLayout(footer); self.update_preview()

    def row(self):
        layout=QHBoxLayout(); layout.setSpacing(8); self.layout.addLayout(layout); return layout

    def slider(self,name,low,high,default,suffix=''):
        row=self.row(); title=QLabel(name); title.setFixedWidth(76); row.addWidget(title)
        slider=QSlider(Qt.Orientation.Horizontal); slider.setRange(low,high); slider.setValue(default); slider.setAccessibleName(name)
        row.addWidget(slider); value=QLabel(f'{default}{suffix}'); value.setFixedWidth(48); value.setAlignment(Qt.AlignmentFlag.AlignRight|Qt.AlignmentFlag.AlignVCenter); row.addWidget(value)
        self.values[name]=slider
        slider.valueChanged.connect(lambda n: value.setText(f'{n}{suffix}'))
        slider.valueChanged.connect(lambda _: self.preview_timer.start())
        row.setContentsMargins(0,4,0,4)

    def ratios(self,row,names,callback):
        for name in names:
            button=QPushButton(name); button.setCheckable(True); button.setChecked(name in ('Free','Auto')); button.setAccessibleName(name+' ratio')
            button.clicked.connect(lambda _checked=False,n=name: callback(n)); row.addWidget(button); self.ratio_buttons.append(button)

    def select_ratio(self,name):
        for button in self.ratio_buttons: button.setChecked(button.text()==name)
        self.ratio=None if name in ('Free','Auto') else float(name.split(':')[0])/float(name.split(':')[1])
        if self.tool=='CROP':
            self.canvas.ratio=self.ratio
            if self.ratio:
                normalized=self.ratio*self.image.height/self.image.width
                w,h=min(1,normalized),min(1,1/normalized); self.canvas.set_crop(((1-w)/2,(1-h)/2,w,h))
        self.preview_timer.start()

    def make_controls(self):
        if self.tool=='CROP':
            row=self.row(); row.addWidget(QLabel('Aspect ratio')); self.ratios(row,('Free','1:1','16:9','9:16','4:3','3:4'),self.select_ratio)
            self.layout.addSpacing(12); row=self.row(); self.width_field=QSpinBox(); self.height_field=QSpinBox()
            for title,field,value in [('W',self.width_field,self.image.width),('H',self.height_field,self.image.height)]:
                row.addWidget(QLabel(title)); field.setRange(1,value); field.setValue(value); field.setFixedWidth(75); field.setAccessibleName('Crop width in pixels' if title=='W' else 'Crop height in pixels'); row.addWidget(field)
            row.addWidget(QLabel('px')); row.addStretch()
            self.canvas.changed.connect(self.update_dimensions)
            self.width_field.valueChanged.connect(self.width_changed); self.height_field.valueChanged.connect(self.height_changed)
        elif self.tool=='ADD BG':
            row=self.row(); label=QLabel('Background'); label.setFixedWidth(76); row.addWidget(label)
            grid=QVBoxLayout(); grid.setSpacing(6); row.addLayout(grid)
            for line in range(2):
                cells=QHBoxLayout(); cells.setSpacing(5); grid.addLayout(cells)
                for index in range(line*9,line*9+9):
                    button=QPushButton(); button.setFixedSize(25,26); button.setAccessibleName(f'Background {index+1}')
                    button.clicked.connect(lambda _checked=False,i=index: self.select_palette(i)); self.swatches.append(button); cells.addWidget(button)
            custom=QPushButton('…'); custom.setFixedSize(24,26); custom.setAccessibleName('Custom background color'); custom.clicked.connect(self.custom_color); row.addWidget(custom)
            self.layout.addSpacing(12)
            self.slider('Padding',0,1000,160,' px'); self.slider('Corners',0,400,40,' px'); self.slider('Shadow',0,100,24,' px')
            row=self.row(); row.addWidget(QLabel('Ratio')); row.addStretch(); self.ratios(row,('Auto','1:1','16:9','4:5'),self.select_ratio)
            self.select_palette(0)
        elif self.tool=='COMPRESS':
            self.slider('Quality',10,100,70,' %'); row=self.row(); row.addWidget(QLabel('Format')); row.addStretch()
            self.format=QComboBox(); self.format.addItems(['JPG','HEIC','WEBP']); row.addWidget(self.format)
            self.layout.addSpacing(10); self.layout.addWidget(QLabel('A separate compressed copy keeps your original safe.'))
        elif self.tool=='EDIT':
            self.slider('Brightness',20,180,100,' %'); self.slider('Contrast',20,200,100,' %'); self.slider('Saturation',0,200,100,' %')
            row=self.row(); rotate=QPushButton('Rotate'); flip=QPushButton('Flip'); row.addWidget(rotate); row.addWidget(flip); row.addStretch()
            rotate.clicked.connect(self.rotate); flip.clicked.connect(self.flip)
        else:
            row=self.row(); row.addWidget(QLabel('Draw on the image.' if self.tool=='ANNOTATE' else 'Drag over areas to cover them permanently.'))
            row.addStretch(); undo=QPushButton('Undo'); undo.clicked.connect(self.undo); row.addWidget(undo)
            self.layout.addSpacing(10); self.layout.addWidget(QLabel('Saved as a separate, flattened PNG.'))

    def update_dimensions(self):
        for field,value in ((self.width_field,round(self.canvas.crop[2]*self.image.width)),(self.height_field,round(self.canvas.crop[3]*self.image.height))):
            field.blockSignals(True); field.setValue(max(1,value)); field.blockSignals(False)

    def width_changed(self,value):
        x,y,_,h=self.canvas.crop; self.canvas.set_crop((x,y,min(1-x,value/self.image.width),h))

    def height_changed(self,value):
        x,y,w,_=self.canvas.crop; h=min(1-y,value/self.image.height)
        if self.ratio: w=min(1-x,h*self.image.height*self.ratio/self.image.width)
        self.canvas.set_crop((x,y,w,h))

    def select_palette(self,index):
        self.palette=index
        for i,button in enumerate(self.swatches):
            colors=PALETTES[i]; gradient=colors[0] if len(colors)==1 else f'qlineargradient(x1:0,y1:0,x2:1,y2:1,stop:0 {colors[0]},stop:1 {colors[-1]})'
            button.setStyleSheet(f'background:{gradient};border:{"2px solid #ed3d0e" if i==index else "1px solid rgba(255,255,255,100)"};border-radius:4px;')
        self.preview_timer.start()

    def custom_color(self):
        color=QColorDialog.getColor(QColor('#446ce0'),self,'Background color')
        if color.isValid(): self.select_palette(-1); self.palette=color.name(); self.preview_timer.start()

    def rotate(self): self.rotation=(self.rotation+1)%4; self.update_preview()
    def flip(self): self.flipped=not self.flipped; self.update_preview()
    def undo(self):
        items=self.canvas.strokes if self.tool=='ANNOTATE' else self.canvas.redactions
        if items: items.pop(); self.canvas.update()

    def rendered(self,preview=False):
        if self.tool=='CROP': return crop_image(self.image,self.canvas.crop)
        if self.tool=='ADD BG': return add_background(self.image,self.palette,self.values['Padding'].value(),self.values['Corners'].value(),self.values['Shadow'].value(),self.ratio,preview)
        if self.tool=='EDIT': return adjust_image(self.image,self.values['Brightness'].value()/100,self.values['Contrast'].value()/100,self.values['Saturation'].value()/100,self.rotation,self.flipped)
        if self.tool in ('ANNOTATE','REDACT'): return self.canvas.flattened()
        return self.image

    def update_preview(self):
        if self.tool in ('ADD BG','EDIT'):
            try: self.canvas.preview=pixmap(self.rendered(preview=True)); self.canvas.update()
            except ValueError as error: QMessageBox.warning(self,'ShiftDrop',str(error))

    def reset(self):
        self.canvas.crop=(0.,0.,1.,1.); self.canvas.ratio=None; self.canvas.strokes=[]; self.canvas.redactions=[]
        self.rotation=0; self.flipped=False
        for name,slider in self.values.items(): slider.setValue({'Padding':160,'Corners':40,'Shadow':24,'Quality':70}.get(name,100))
        if self.tool=='CROP': self.select_ratio('Free'); self.update_dimensions()
        if self.tool=='ADD BG': self.select_palette(0); self.select_ratio('Auto')
        self.canvas.update(); self.update_preview()

    def save(self):
        if self.tool=='METADATA': self.close(); return
        suffix={'CROP':' Cropped','ADD BG':' Background','COMPRESS':' Compressed','EDIT':' Edited','ANNOTATE':' Annotated','REDACT':' Redacted'}[self.tool]
        format_name=self.format.currentText() if self.tool=='COMPRESS' else 'JPG' if self.tool=='CROP' and self.source.suffix.lower() in ('.jpg','.jpeg') else 'PNG'
        quality=self.values['Quality'].value()/100 if self.tool=='COMPRESS' else .94
        try: image=self.rendered()
        except (ValueError,OSError) as error: QMessageBox.warning(self,'ShiftDrop',str(error)); return
        self.saved.emit(image,suffix,format_name,quality); self.close()
